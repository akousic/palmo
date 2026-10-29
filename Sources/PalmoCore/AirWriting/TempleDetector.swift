import Foundation

/// The face as seen by the camera, in the same mirrored, normalized coordinates as `HandPose` (y up).
public struct FaceGeometry: Sendable, Hashable {
    /// Face bounding box.
    public var rect: Rect2D
    /// Outer corner of the eye on the left of the (mirrored) image, if face landmarks were detected.
    public var leftEyeOuter: Point2D?
    /// Outer corner of the eye on the right of the (mirrored) image, if face landmarks were detected.
    public var rightEyeOuter: Point2D?

    /// Creates a face geometry.
    public init(rect: Rect2D, leftEyeOuter: Point2D? = nil, rightEyeOuter: Point2D? = nil) {
        self.rect = rect
        self.leftEyeOuter = leftEyeOuter
        self.rightEyeOuter = rightEyeOuter
    }
}

/// Which temple is touched, in image (user-perspective) terms.
public enum TempleSide: Sendable, Hashable {
    case left, right
}

/// An elliptical target region around one temple.
public struct TempleZone: Sendable, Hashable {
    /// Side of the face.
    public var side: TempleSide
    /// Center of the zone.
    public var center: Point2D
    /// Horizontal radius.
    public var radiusX: Double
    /// Vertical radius.
    public var radiusY: Double

    /// Whether `p` is inside the ellipse.
    public func contains(_ p: Point2D) -> Bool {
        let dx = (p.x - center.x) / radiusX, dy = (p.y - center.y) / radiusY
        return dx * dx + dy * dy <= 1
    }
}

/// Finds the temples next to the eyes and decides whether the index fingertip is touching one.
///
/// This is a deliberate, narrow exception to the face-zone guard: only the index fingertip counts, the index
/// finger must be extended, and the point must sit in a small zone just outside the outer eye corner.
public struct TempleDetector: Sendable {
    /// Horizontal distance from the outer eye corner to the temple center, in face widths.
    public var lateralOffset = 0.10
    /// Height of the temple center above the outer eye corner, in face heights.
    public var lift = 0.06
    /// Zone radii in face widths / heights.
    public var radiusX = 0.17
    public var radiusY = 0.15
    /// Minimum index extension ratio (tip-to-wrist / PIP-to-wrist).
    public var minIndexExtension = 1.05
    /// Minimum confidence of the index fingertip.
    public var minTipConfidence = 0.3

    /// Creates a detector with default geometry.
    public init() {}

    /// The two temple zones for a face.
    public func zones(for face: FaceGeometry) -> [TempleZone] {
        let r = face.rect, w = r.width, h = r.height
        // Without landmarks, the eyes sit about 62 % up the face box and 12 % in from its sides.
        let leftEye = face.leftEyeOuter ?? Point2D(x: r.minX + 0.12 * w, y: r.minY + 0.62 * h)
        let rightEye = face.rightEyeOuter ?? Point2D(x: r.minX + 0.88 * w, y: r.minY + 0.62 * h)
        return [
            TempleZone(side: .left, center: Point2D(x: leftEye.x - lateralOffset * w, y: leftEye.y + lift * h),
                       radiusX: radiusX * w, radiusY: radiusY * h),
            TempleZone(side: .right, center: Point2D(x: rightEye.x + lateralOffset * w, y: rightEye.y + lift * h),
                       radiusX: radiusX * w, radiusY: radiusY * h),
        ]
    }

    /// The temple the index fingertip is touching, if any.
    public func touchedSide(pose: HandPose, face: FaceGeometry) -> TempleSide? {
        guard pose.confidence(.indexTip) >= minTipConfidence,
              (PoseMetrics(pose).fingerExtension[.index] ?? 0) >= minIndexExtension else { return nil }
        let tip = pose[.indexTip]
        return zones(for: face).first { $0.contains(tip) }?.side
    }
}

/// A dwell timer for deliberate holds: fires once after `dwell` seconds of (mostly) continuous contact,
/// tolerates gaps up to `grace`, and won't fire again until contact is released.
public struct GestureHold: Sendable {
    /// Seconds of contact needed.
    public var dwell: Double
    /// Longest tolerated gap in contact.
    public var grace: Double
    /// Minimum seconds between firings.
    public var cooldown: Double
    /// Progress `0...1` of the current hold.
    public private(set) var progress: Double = 0

    private var start: TimeInterval?
    private var lastHit: TimeInterval?
    private var latched = false
    private var lastFire: TimeInterval = -.infinity

    /// Creates a hold timer.
    public init(dwell: Double, grace: Double = 0.15, cooldown: Double = 1.0) {
        self.dwell = dwell
        self.grace = grace
        self.cooldown = cooldown
    }

    /// Feeds one frame; returns `true` on the frame the hold completes.
    public mutating func update(active: Bool, at t: TimeInterval) -> Bool {
        if let lastHit, t - lastHit > grace {
            start = nil
            progress = 0
            latched = false
        }
        guard active else { return false }
        lastHit = t
        if latched { return false }
        if start == nil { start = t }
        let held = t - start!
        progress = min(held / dwell, 1)
        if held >= dwell - 1e-9, t - lastFire >= cooldown {
            latched = true
            lastFire = t
            start = nil
            progress = 0
            return true
        }
        return false
    }

    /// Clears the hold (keeps the cooldown).
    public mutating func reset() {
        start = nil
        lastHit = nil
        latched = false
        progress = 0
    }
}
