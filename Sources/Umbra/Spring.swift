import Foundation
import QuartzCore

/// Closed-form spring step response: goes from 0 at t = 0 to 1 as t grows.
/// `response` is the period of the undamped spring in seconds, `damping` is the damping ratio (1 = no overshoot).
struct Spring {
    var response: Double = 0.5
    var damping: Double = 0.88 // about 0.3% overshoot: a tiny one at most

    private var omega: Double { 2 * .pi / response }

    func step(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let w = omega, z = damping
        if z >= 1 {
            return 1 - exp(-w * t) * (1 + w * t)
        }
        let wd = w * (1 - z * z).squareRoot()
        return 1 - exp(-z * w * t) * (cos(wd * t) + (z * w / wd) * sin(wd * t))
    }

    /// Time after which the step is within 0.1% of 1.
    var settleTime: Double { log(1000) / (min(damping, 1) * omega) }
}

/// A value that can change target many times. It is the sum of one spring per change,
/// so its value is a pure function of time and a new target never restarts or jumps the motion.
struct SpringTrack {
    var spring = Spring()
    private(set) var base: Double
    private var steps: [(start: Double, delta: Double)] = []

    init(_ value: Double, spring: Spring = Spring()) {
        base = value
        self.spring = spring
    }

    /// Where the value ends up once every spring settles.
    var target: Double { base + steps.reduce(0) { $0 + $1.delta } }

    func value(at t: Double) -> Double {
        steps.reduce(base) { $0 + $1.delta * spring.step(t - $1.start) }
    }

    func isSettled(at t: Double) -> Bool {
        steps.allSatisfy { t - $0.start >= spring.settleTime }
    }

    /// Add a spring from the current final target to `newTarget`, starting at `t`.
    mutating func retarget(_ newTarget: Double, at t: Double) {
        prune(at: t)
        let delta = newTarget - target
        if abs(delta) > 1e-9 { steps.append((t, delta)) }
    }

    /// Jump to `value` with no motion.
    mutating func reset(_ value: Double) {
        base = value
        steps = []
    }

    /// Fold settled springs into the base so the list stays short.
    mutating func prune(at t: Double) {
        let done = steps.filter { t - $0.start >= spring.settleTime }
        guard !done.isEmpty else { return }
        base += done.reduce(0) { $0 + $1.delta }
        steps.removeAll { t - $0.start >= spring.settleTime }
    }

    static var now: Double { CACurrentMediaTime() }
}
