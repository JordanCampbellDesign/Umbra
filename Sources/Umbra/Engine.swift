import AppKit
import CoreLocation
import Foundation

/// Runs the adaptive modes and pushes target values to displays that have adaptive on.
final class Engine: NSObject, CLLocationManagerDelegate {
    static let shared = Engine()

    private var timer: Timer?
    private var lastSource: Double?
    private(set) var targets: [String: Double] = [:] // display uuid -> last adaptive brightness before offset
    private var location: CLLocationManager?
    @objc dynamic var sensorLux: Double = -1
    var paused = false

    private var state: AppState { AppState.shared }
    private var settings: AppSettings { state.settings }

    func restart() {
        timer?.invalidate()
        lastSource = nil
        let interval: Double
        switch settings.mode {
        case .manual: return
        case .sync:
            // macOS tells us when the source's brightness changes, so only a slow backup check is needed.
            // Without the notification, fall back to polling.
            let watched = syncSource.map { Private.watchBrightness($0.id) } ?? false
            interval = watched ? 3 : max(0.2, settings.syncPollSeconds)
        case .sensor: interval = 2
        case .location, .clock: interval = 30
        }
        tick(force: true)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick(force: false) }
        // Slack lets macOS group this wake-up with other work, which saves energy.
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stop the timers, for example while the screens are asleep. `restart()` starts them again.
    func suspend() {
        timer?.invalidate()
        timer = nil
    }

    private func targetDisplays(excluding source: Display? = nil) -> [Display] {
        state.displays.filter { $0.config.adaptive && !$0.blackedOut && $0.id != source?.id }
    }

    func tick(force: Bool) {
        guard !paused, !state.faceLightOn else { return }
        switch settings.mode {
        case .manual: return
        case .sync: syncTick(force: force)
        case .location: locationTick()
        case .clock: clockTick()
        case .sensor: sensorTick()
        }
    }

    // MARK: Sync

    var syncSource: Display? {
        if !settings.syncSource.isEmpty, let d = state.displays.first(where: { $0.uuid == settings.syncSource }) { return d }
        return state.displays.first { $0.isBuiltin } ?? state.displays.first { $0.method == .appleNative }
    }

    /// Called on the main thread when macOS reports a brightness change on a watched display.
    func brightnessChanged() {
        guard settings.mode == .sync else { return }
        tick(force: false)
    }

    private func syncTick(force: Bool) {
        guard let src = syncSource, let b = src.readSystemBrightness() else { return }
        if !force, let last = lastSource, abs(last - b) < 0.4 { return }
        lastSource = b
        src.config.brightness = b
        for d in targetDisplays(excluding: src) { push(d, brightness: b, contrast: nil, animated: false) }
    }

    // MARK: Location

    func requestLocation() {
        if location == nil {
            location = CLLocationManager()
            location?.delegate = self
        }
        location?.requestWhenInUseAuthorization()
        location?.requestLocation()
    }

    func locationManager(_: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let l = locs.last else { return }
        state.settings.latitude = l.coordinate.latitude
        state.settings.longitude = l.coordinate.longitude
        state.settings.hasLocation = true
        tick(force: true)
    }

    func locationManager(_: CLLocationManager, didFailWithError error: Error) {
        NSLog("Umbra location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorized || m.authorizationStatus == .authorizedAlways { m.requestLocation() }
    }

    /// Brightness 0..100 from sun height. Dark below civil twilight, full at solar noon.
    func locationBrightness(at date: Date = Date()) -> Double? {
        guard settings.hasLocation else { return nil }
        let lat = settings.latitude, lon = settings.longitude
        let e = Sun.elevation(at: date, lat: lat, lon: lon)
        let peak = max(5, Sun.times(on: date, lat: lat, lon: lon).noonElevation)
        let f = max(0, min(1, (e + 6) / (peak + 6)))
        return pow(f, 0.75) * 100
    }

    private func locationTick() {
        guard let b = locationBrightness() else { requestLocation(); return }
        for d in targetDisplays() { push(d, brightness: b, contrast: nil, animated: true) }
    }

    // MARK: Clock

    func date(for item: ScheduleItem, on day: Date) -> Date? {
        let start = Calendar.current.startOfDay(for: day)
        let base: Date?
        switch item.anchor {
        case .time:
            base = Calendar.current.date(bySettingHour: item.hour, minute: item.minute, second: 0, of: start)
        case .sunrise, .noon, .sunset:
            guard settings.hasLocation else { return nil }
            let t = Sun.times(on: start, lat: settings.latitude, lon: settings.longitude)
            base = item.anchor == .sunrise ? t.sunrise : item.anchor == .noon ? t.noon : t.sunset
        }
        return base?.addingTimeInterval(Double(item.offsetMinutes) * 60)
    }

    /// Current (brightness, contrast) from the schedule.
    func clockValues(at now: Date = Date()) -> (Double, Double)? {
        let cal = Calendar.current
        var points: [(Date, ScheduleItem)] = []
        for dayOffset in -1 ... 1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            for item in settings.schedule where item.enabled {
                if let d = date(for: item, on: day) { points.append((d, item)) }
            }
        }
        points.sort { $0.0 < $1.0 }
        guard let prevIdx = points.lastIndex(where: { $0.0 <= now }) else { return nil }
        let prev = points[prevIdx]
        guard settings.smoothClock, prevIdx + 1 < points.count else { return (prev.1.brightness, prev.1.contrast) }
        let next = points[prevIdx + 1]
        let f = now.timeIntervalSince(prev.0) / next.0.timeIntervalSince(prev.0)
        return (prev.1.brightness + (next.1.brightness - prev.1.brightness) * f,
                prev.1.contrast + (next.1.contrast - prev.1.contrast) * f)
    }

    private func clockTick() {
        if settings.schedule.contains(where: { $0.anchor != .time }), !settings.hasLocation { requestLocation() }
        guard let (b, c) = clockValues() else { return }
        for d in targetDisplays() { push(d, brightness: b, contrast: c, animated: true) }
    }

    // MARK: Sensor

    private func sensorTick() {
        guard !settings.sensorURL.isEmpty, let url = URL(string: settings.sensorURL) else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 2)) { [weak self] data, _, _ in
            guard let self, let data, let lux = Self.parseLux(data) else { return }
            DispatchQueue.main.async {
                self.sensorLux = lux
                let b = min(100, log10(1 + lux) / log10(1 + max(10, self.settings.sensorMaxLux)) * 100)
                for d in self.targetDisplays() { self.push(d, brightness: b, contrast: nil, animated: true) }
            }
        }.resume()
    }

    static func parseLux(_ data: Data) -> Double? {
        if let obj = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            if let n = obj as? NSNumber { return n.doubleValue }
            if let d = obj as? [String: Any] {
                for k in ["lux", "illuminance", "value", "state"] {
                    if let n = d[k] as? NSNumber { return n.doubleValue }
                    if let s = d[k] as? String, let v = Double(s) { return v }
                }
            }
        }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(s)
    }

    // MARK: Apply

    private func push(_ d: Display, brightness: Double, contrast: Double?, animated: Bool) {
        targets[d.uuid] = brightness
        let b = max(0, min(100, brightness + d.config.syncOffset))
        if abs(d.config.brightness - b) >= 0.5 { d.setBrightness(b, animated: animated) }
        // When the mode gives no contrast, it can follow brightness: a little lower in the dark, like Lunar does.
        let c = contrast ?? (settings.contrastFollowsBrightness ? settings.followContrastMin + (settings.followContrastMax - settings.followContrastMin) * b / 100 : nil)
        if let c, d.hasHardwareControls, abs(d.config.contrast - c) >= 0.5 { d.setContrast(c) }
    }

    /// Called when the user moves a slider while an adaptive mode runs: learn the offset for next time.
    func userAdjusted(_ d: Display, brightness: Double) {
        guard settings.mode != .manual, d.config.adaptive else { return }
        if settings.mode == .sync, d.id == syncSource?.id { return }
        guard let t = targets[d.uuid] else { return }
        d.config.syncOffset = max(-100, min(100, brightness - t))
    }
}
