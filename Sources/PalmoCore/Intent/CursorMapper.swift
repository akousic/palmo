import Foundation

/// A rectangle in global display coordinates (points, origin top-left of the main display).
public struct ScreenRect: Sendable, Hashable {
    /// Minimum x.
    public var minX: Double
    /// Minimum y.
    public var minY: Double
    /// Maximum x.
    public var maxX: Double
    /// Maximum y.
    public var maxY: Double

    /// Creates a rectangle.
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    /// Width in points.
    public var width: Double { maxX - minX }

    /// Clamps a point into the rectangle.
    public func clamp(x: Double, y: Double) -> (x: Double, y: Double) {
        (min(max(x, minX), maxX - 1), min(max(y, minY), maxY - 1))
    }
}

extension ScreenRect {
    /// Horizontal center.
    public var midX: Double { (minX + maxX) / 2 }
    /// Vertical center.
    public var midY: Double { (minY + maxY) / 2 }
    /// Whether the point lies inside (edges included).
    public func contains(x: Double, y: Double) -> Bool { x >= minX && x <= maxX && y >= minY && y <= maxY }
}

/// Converts hand control-point motion into relative cursor motion, like a trackpad.
///
/// Relative mapping lets the hand stay in a small, comfortable box at desk height. To reposition
/// ("clutch"), lower the hand or relax the index finger, move, and point again: any pause longer than
/// `clutchGap` re-anchors without moving the cursor.
///
/// Speed follows an acceleration curve. Slow hand motion is scaled down by `precision` for fine
/// aiming at small targets such as window buttons; fast motion is scaled up by `1 + acceleration`
/// for travel across the screen. A dedicated One Euro filter removes jitter when the hand is nearly
/// still while staying responsive when it moves.
public struct CursorMapper: Sendable {
    /// Speed multiplier (settings `cursorGain`).
    public var gain: Double
    /// Gain fraction used at slow hand speeds (`0.15...1`).
    public var precision: Double
    /// Extra gain reached at fast hand speeds.
    public var acceleration: Double
    /// Hand speed (normalized units per second) at or below which full precision applies.
    public var slowSpeed: Double
    /// Hand speed at or above which full acceleration applies.
    public var fastSpeed: Double
    /// Movement below this (normalized) is not applied yet; it accumulates until it exceeds the threshold.
    public var deadZone: Double
    /// A gap longer than this re-anchors without moving (clutch).
    public var clutchGap: TimeInterval
    /// Smoothing amount `0...1` for the dedicated pointer filter.
    public var smoothing: Double {
        didSet { rebuildFilters() }
    }

    private var last: Point2D?
    private var lastTime: TimeInterval?
    private var filterX = OneEuroFilter()
    private var filterY = OneEuroFilter()

    /// Creates a mapper.
    public init(gain: Double = 1.4, precision: Double = 0.35, acceleration: Double = 1.6,
                smoothing: Double = 0.5, slowSpeed: Double = 0.05, fastSpeed: Double = 0.8,
                deadZone: Double = 0.0006, clutchGap: TimeInterval = 0.25) {
        self.gain = gain
        self.precision = precision
        self.acceleration = acceleration
        self.smoothing = smoothing
        self.slowSpeed = slowSpeed
        self.fastSpeed = fastSpeed
        self.deadZone = deadZone
        self.clutchGap = clutchGap
        rebuildFilters()
    }

    /// Applies pointer settings.
    public mutating func configure(with settings: PalmoSettings) {
        let s = settings.sanitized()
        gain = s.cursorGain
        precision = s.pointerPrecision
        acceleration = s.pointerAcceleration
        smoothing = s.pointerSmoothing
    }

    /// Forgets the anchor; the next sample only re-anchors.
    public mutating func reset() {
        last = nil
        lastTime = nil
        filterX.reset()
        filterY.reset()
    }

    /// The gain multiplier for a hand speed: `precision` when slow, rising smoothly to `1 + acceleration` when fast.
    public func speedFactor(forSpeed speed: Double) -> Double {
        let t = min(max((speed - slowSpeed) / (fastSpeed - slowSpeed), 0), 1)
        let eased = t * t * (3 - 2 * t)
        return precision + (1 + acceleration - precision) * eased
    }

    /// Tracks the hand without moving the cursor (used while a pinch is forming so the click doesn't drift).
    public mutating func hold(handPoint: Point2D, at time: TimeInterval) {
        last = smooth(handPoint, at: time)
        lastTime = time
    }

    /// Returns the new cursor position given the hand point, the current cursor and the screen bounds,
    /// or `nil` if the cursor should not move this frame. `friction` (`0...1`) scales the motion down,
    /// for example while the cursor is over a button.
    public mutating func update(handPoint: Point2D, at time: TimeInterval,
                                cursor: (x: Double, y: Double), bounds: ScreenRect,
                                friction: Double = 1) -> (x: Double, y: Double)? {
        if let previousTime = lastTime, time - previousTime > clutchGap { reset() }
        let p = smooth(handPoint, at: time)
        guard let previous = last, let previousTime = lastTime else {
            last = p
            lastTime = time
            return nil
        }
        let d = p - previous
        let magnitude = hypot(d.x, d.y)
        guard magnitude > deadZone else { return nil }
        last = p
        lastTime = time
        let dt = max(time - previousTime, 1.0 / 120)
        let scale = bounds.width * gain * speedFactor(forSpeed: magnitude / dt) * min(max(friction, 0), 1)
        // Hand space is y-up; screen space is y-down.
        return bounds.clamp(x: cursor.x + d.x * scale, y: cursor.y - d.y * scale)
    }

    /// Smoothing 0 passes the point through untouched.
    private mutating func smooth(_ p: Point2D, at time: TimeInterval) -> Point2D {
        guard smoothing > 0.001 else { return p }
        return Point2D(x: filterX.filter(p.x, at: time), y: filterY.filter(p.y, at: time))
    }

    private mutating func rebuildFilters() {
        // More smoothing lowers the cutoff at rest; beta keeps fast motion responsive.
        let s = min(max(smoothing, 0), 1)
        let minCutoff = 3.0 - 2.6 * s
        filterX = OneEuroFilter(minCutoff: minCutoff, beta: 12)
        filterY = OneEuroFilter(minCutoff: minCutoff, beta: 12)
    }
}
