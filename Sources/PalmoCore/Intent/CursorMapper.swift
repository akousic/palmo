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

/// Converts hand control-point motion into relative cursor motion, like a trackpad.
///
/// Relative mapping lets the hand stay in a small, comfortable box at desk height ("clutching"
/// by pausing or lowering the hand), instead of reaching for screen corners.
public struct CursorMapper: Sendable {
    /// Speed multiplier (settings `cursorGain`).
    public var gain: Double
    /// Pointer acceleration exponent factor.
    public var acceleration: Double
    /// Movement below this (normalized) is ignored to kill residual jitter.
    public var deadZone: Double
    /// A gap longer than this re-anchors without moving (clutch).
    public var clutchGap: TimeInterval

    private var last: Point2D?
    private var lastTime: TimeInterval?

    /// Creates a mapper.
    public init(gain: Double = 1.4, acceleration: Double = 2.5, deadZone: Double = 0.0015, clutchGap: TimeInterval = 0.25) {
        self.gain = gain
        self.acceleration = acceleration
        self.deadZone = deadZone
        self.clutchGap = clutchGap
    }

    /// Forgets the anchor; the next sample only re-anchors.
    public mutating func reset() {
        last = nil
        lastTime = nil
    }

    /// Returns the new cursor position given the hand point, the current cursor and the screen bounds,
    /// or `nil` if the cursor should not move this frame.
    public mutating func update(handPoint: Point2D, at time: TimeInterval,
                                cursor: (x: Double, y: Double), bounds: ScreenRect) -> (x: Double, y: Double)? {
        defer {
            lastTime = time
        }
        guard let previous = last, let previousTime = lastTime, time - previousTime <= clutchGap else {
            last = handPoint
            return nil
        }
        let d = handPoint - previous
        let magnitude = hypot(d.x, d.y)
        guard magnitude > deadZone else { return nil }
        last = handPoint
        let dt = max(time - previousTime, 1.0 / 120)
        let speed = magnitude / dt
        let accel = 1 + acceleration * min(speed, 2)
        let scale = bounds.width * gain * accel
        // Hand space is y-up; screen space is y-down.
        return bounds.clamp(x: cursor.x + d.x * scale, y: cursor.y - d.y * scale)
    }
}
