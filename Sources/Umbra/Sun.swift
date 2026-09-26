import Foundation

/// Solar position from a low-precision almanac formula (accurate to about 0.1 degree).
enum Sun {
    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
    private static func norm(_ x: Double, _ m: Double) -> Double { let r = x.truncatingRemainder(dividingBy: m); return r < 0 ? r + m : r }

    /// Sun elevation above the horizon in degrees.
    static func elevation(at date: Date, lat: Double, lon: Double) -> Double {
        let n = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let L = norm(280.460 + 0.9856474 * n, 360)
        let g = rad(norm(357.528 + 0.9856003 * n, 360))
        let lambda = rad(L + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let eps = rad(23.439 - 0.0000004 * n)
        let ra = atan2(cos(eps) * sin(lambda), cos(lambda))
        let dec = asin(sin(eps) * sin(lambda))
        let gmst = norm(18.697374558 + 24.06570982441908 * n, 24)
        let ha = rad(norm(gmst * 15 + lon, 360)) - ra
        let latR = rad(lat)
        return deg(asin(sin(latR) * sin(dec) + cos(latR) * cos(dec) * cos(ha)))
    }

    struct Times { let sunrise: Date?; let noon: Date; let sunset: Date?; let noonElevation: Double }

    private static var cache: (key: String, value: Times)?

    /// Sunrise, solar noon, and sunset for the local calendar day that contains `date`.
    static func times(on date: Date, lat: Double, lon: Double) -> Times {
        let start = Calendar.current.startOfDay(for: date)
        let key = "\(start.timeIntervalSince1970)-\(lat)-\(lon)"
        if let c = cache, c.key == key { return c.value }
        var noon = start, noonEl = -90.0
        var sunrise: Date?, sunset: Date?
        var prev = elevation(at: start, lat: lat, lon: lon)
        for m in 1 ... 1440 {
            let t = start.addingTimeInterval(Double(m) * 60)
            let e = elevation(at: t, lat: lat, lon: lon)
            if e > noonEl { noonEl = e; noon = t }
            if prev < -0.833, e >= -0.833, sunrise == nil { sunrise = t }
            if prev >= -0.833, e < -0.833 { sunset = t }
            prev = e
        }
        let v = Times(sunrise: sunrise, noon: noon, sunset: sunset, noonElevation: noonEl)
        cache = (key, v)
        return v
    }
}
