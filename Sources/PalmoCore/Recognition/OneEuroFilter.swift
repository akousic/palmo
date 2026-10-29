import Foundation

/// The One Euro filter (Casiez, Roussel & Vogel, CHI 2012): a speed-adaptive low-pass filter.
///
/// At low speeds it smooths heavily (removing jitter); at high speeds it follows closely (removing lag).
public struct OneEuroFilter: Sendable {
    /// Minimum cutoff frequency in Hz. Lower = smoother when still.
    public var minCutoff: Double
    /// Speed coefficient. Higher = less lag when moving fast.
    public var beta: Double
    /// Cutoff frequency for the derivative, in Hz.
    public var derivativeCutoff: Double

    private var lastValue: Double?
    private var lastDerivative: Double = 0
    private var lastTime: TimeInterval?

    /// Creates a filter.
    public init(minCutoff: Double = 1.0, beta: Double = 0.007, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2 * Double.pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    /// Filters a sample taken at `time` (seconds) and returns the smoothed value.
    public mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let previous = lastValue, let previousTime = lastTime, time > previousTime else {
            lastValue = value
            lastTime = time
            lastDerivative = 0
            return value
        }
        let dt = time - previousTime
        let derivative = (value - previous) / dt
        let aD = Self.alpha(cutoff: derivativeCutoff, dt: dt)
        let smoothedDerivative = aD * derivative + (1 - aD) * lastDerivative
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let result = a * value + (1 - a) * previous
        lastValue = result
        lastDerivative = smoothedDerivative
        lastTime = time
        return result
    }

    /// Forgets history so the next sample passes through unchanged.
    public mutating func reset() {
        lastValue = nil
        lastTime = nil
        lastDerivative = 0
    }
}

/// Applies independent One Euro filters to every coordinate of every hand landmark.
public struct HandPoseSmoother: Sendable {
    private var filters: [OneEuroFilter]
    private var lastTimestamp: TimeInterval?

    /// Creates a smoother. Defaults are tuned for normalized coordinates at ~30 fps.
    public init(minCutoff: Double = 1.2, beta: Double = 18, derivativeCutoff: Double = 1.0) {
        filters = Array(repeating: OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff),
                        count: Joint.allCases.count * 2)
    }

    /// Smooths a pose. A gap longer than half a second resets the filters.
    public mutating func smooth(_ pose: HandPose) -> HandPose {
        if let last = lastTimestamp, pose.timestamp - last > 0.5 { reset() }
        lastTimestamp = pose.timestamp
        var landmarks = pose.landmarks
        for i in landmarks.indices {
            let p = landmarks[i].location
            let x = filters[i * 2].filter(p.x, at: pose.timestamp)
            let y = filters[i * 2 + 1].filter(p.y, at: pose.timestamp)
            landmarks[i].location = Point2D(x: x, y: y)
        }
        return HandPose(landmarks: landmarks, chirality: pose.chirality, timestamp: pose.timestamp)
    }

    /// Clears all filter state.
    public mutating func reset() {
        for i in filters.indices { filters[i].reset() }
        lastTimestamp = nil
    }
}
