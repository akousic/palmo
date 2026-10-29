import Foundation

/// A 2-D point in normalized, user-perspective image space.
///
/// `x` grows to the user's right (the camera image is mirrored in software) and
/// `y` grows upward, both in `0...1`.
public struct Point2D: Sendable, Hashable, Codable {
    /// Horizontal coordinate.
    public var x: Double
    /// Vertical coordinate.
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The Euclidean distance to another point.
    public func distance(to other: Point2D) -> Double {
        hypot(x - other.x, y - other.y)
    }

    /// Component-wise addition.
    public static func + (lhs: Point2D, rhs: Point2D) -> Point2D { Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y) }
    /// Component-wise subtraction.
    public static func - (lhs: Point2D, rhs: Point2D) -> Point2D { Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }
    /// Scalar multiplication.
    public static func * (lhs: Point2D, rhs: Double) -> Point2D { Point2D(x: lhs.x * rhs, y: lhs.y * rhs) }

    /// The midpoint between two points.
    public static func midpoint(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
}

/// An axis-aligned rectangle in normalized user-perspective image space.
public struct Rect2D: Sendable, Hashable, Codable {
    /// Minimum x.
    public var minX: Double
    /// Minimum y.
    public var minY: Double
    /// Width.
    public var width: Double
    /// Height.
    public var height: Double

    /// Creates a rectangle.
    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    /// Returns a copy shrunk by `amount` on every side (a negative amount grows it).
    public func insetBy(_ amount: Double) -> Rect2D {
        Rect2D(minX: minX + amount, minY: minY + amount, width: width - 2 * amount, height: height - 2 * amount)
    }

    /// Whether the point lies inside the rectangle.
    public func contains(_ p: Point2D) -> Bool {
        p.x >= minX && p.x <= minX + width && p.y >= minY && p.y <= minY + height
    }
}

/// The 21 hand landmarks reported by Vision, in Vision's documented anatomical order.
public enum Joint: Int, CaseIterable, Sendable, Codable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip
}

/// The four non-thumb fingers.
public enum Finger: Int, CaseIterable, Sendable, Codable {
    case index, middle, ring, little

    /// The knuckle joint of this finger.
    public var mcp: Joint { Joint(rawValue: 5 + rawValue * 4)! }
    /// The middle joint of this finger.
    public var pip: Joint { Joint(rawValue: 6 + rawValue * 4)! }
    /// The distal joint of this finger.
    public var dip: Joint { Joint(rawValue: 7 + rawValue * 4)! }
    /// The fingertip.
    public var tip: Joint { Joint(rawValue: 8 + rawValue * 4)! }
}

/// Which hand Vision believes it saw.
public enum Chirality: String, Sendable, Codable {
    case left, right, unknown
}

/// A single landmark with Vision's confidence.
public struct Landmark: Sendable, Hashable, Codable {
    /// Location in normalized user-perspective space.
    public var location: Point2D
    /// Vision confidence, `0...1`.
    public var confidence: Double

    /// Creates a landmark.
    public init(location: Point2D, confidence: Double) {
        self.location = location
        self.confidence = confidence
    }
}

/// One observed hand at one instant. A value type that crosses actor boundaries freely.
public struct HandPose: Sendable, Hashable, Codable {
    /// Landmarks indexed by `Joint.rawValue`; always 21 entries.
    public var landmarks: [Landmark]
    /// Reported handedness.
    public var chirality: Chirality
    /// Capture time in seconds (monotonic media time).
    public var timestamp: TimeInterval

    /// Creates a pose. `landmarks` must contain exactly 21 entries.
    public init(landmarks: [Landmark], chirality: Chirality, timestamp: TimeInterval) {
        precondition(landmarks.count == Joint.allCases.count, "HandPose needs 21 landmarks")
        self.landmarks = landmarks
        self.chirality = chirality
        self.timestamp = timestamp
    }

    /// The location of a joint.
    public subscript(_ joint: Joint) -> Point2D { landmarks[joint.rawValue].location }

    /// Confidence of a joint.
    public func confidence(_ joint: Joint) -> Double { landmarks[joint.rawValue].confidence }

    /// Mean confidence across all joints.
    public var meanConfidence: Double { landmarks.map(\.confidence).reduce(0, +) / Double(landmarks.count) }

    /// A scale reference: wrist to middle knuckle distance.
    public var handSize: Double { max(self[.wrist].distance(to: self[.middleMCP]), 1e-4) }

    /// Centroid of all landmarks.
    public var centroid: Point2D {
        let sum = landmarks.reduce(Point2D(x: 0, y: 0)) { $0 + $1.location }
        return sum * (1.0 / Double(landmarks.count))
    }

    /// Returns a copy with every landmark transformed.
    public func mapped(_ transform: (Point2D) -> Point2D) -> HandPose {
        HandPose(landmarks: landmarks.map { Landmark(location: transform($0.location), confidence: $0.confidence) },
                 chirality: chirality, timestamp: timestamp)
    }
}
