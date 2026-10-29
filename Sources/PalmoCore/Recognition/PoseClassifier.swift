import Foundation

/// A static hand shape recognized from a single frame.
public enum HandShape: String, Sendable, Hashable, Codable, CaseIterable {
    /// All five digits extended and spread.
    case openPalm
    /// All fingers curled, thumb tucked.
    case fist
    /// Only the index finger extended.
    case pointing
    /// Thumb tip touching index tip (other fingers not all extended).
    case indexPinch
    /// Thumb tip touching middle tip while the index stays clear.
    case middlePinch
    /// Index and middle extended and held together.
    case twoFingers
    /// Index and middle extended and spread in a V.
    case peace
    /// Index, middle and ring extended.
    case threeFingers
    /// Thumb out sideways, fingers curled ("hitchhiker").
    case thumbOut
    /// Thumb pointing up, fingers curled.
    case thumbsUp
    /// Thumb–index pinch with the other three fingers extended (the "dial").
    case dial
    /// No confident match.
    case unknown
}

/// Scale-invariant measurements of a pose that the rules are built on.
public struct PoseMetrics: Sendable, Hashable {
    /// Per-finger extension ratio: distance(tip, wrist) / distance(pip, wrist). >1.2 extended, <1.0 curled.
    public var fingerExtension: [Finger: Double]
    /// Thumb tip to index knuckle, in hand sizes.
    public var thumbToIndexMCP: Double
    /// Thumb tip to little knuckle, in hand sizes.
    public var thumbToLittleMCP: Double
    /// Thumb tip to index tip, in hand sizes.
    public var thumbIndexGap: Double
    /// Thumb tip to middle tip, in hand sizes.
    public var thumbMiddleGap: Double
    /// Index tip to middle tip, in hand sizes.
    public var indexMiddleSpread: Double
    /// Index tip to little tip, in hand sizes.
    public var fanSpread: Double
    /// Height of the thumb tip above the index knuckle, in hand sizes.
    public var thumbRise: Double
    /// Sign of the palm's normal relative to the camera (+1 / -1); flips when the hand turns over.
    public var palmSide: Int
    /// Wrist roll angle (radians) of the index-knuckle → little-knuckle vector.
    public var rollAngle: Double

    /// Computes metrics from a pose.
    public init(_ pose: HandPose) {
        let size = pose.handSize
        let wrist = pose[.wrist]
        var ext: [Finger: Double] = [:]
        for finger in Finger.allCases {
            let tip = pose[finger.tip].distance(to: wrist)
            let pip = max(pose[finger.pip].distance(to: wrist), 1e-4)
            ext[finger] = tip / pip
        }
        self.fingerExtension = ext
        thumbToIndexMCP = pose[.thumbTip].distance(to: pose[.indexMCP]) / size
        thumbToLittleMCP = pose[.thumbTip].distance(to: pose[.littleMCP]) / size
        thumbIndexGap = pose[.thumbTip].distance(to: pose[.indexTip]) / size
        thumbMiddleGap = pose[.thumbTip].distance(to: pose[.middleTip]) / size
        indexMiddleSpread = pose[.indexTip].distance(to: pose[.middleTip]) / size
        fanSpread = pose[.indexTip].distance(to: pose[.littleTip]) / size
        thumbRise = (pose[.thumbTip].y - pose[.indexMCP].y) / size
        let a = pose[.indexMCP] - wrist
        let b = pose[.littleMCP] - wrist
        palmSide = (a.x * b.y - a.y * b.x) >= 0 ? 1 : -1
        let roll = pose[.littleMCP] - pose[.indexMCP]
        rollAngle = atan2(roll.y, roll.x)
    }
}

/// Tunable thresholds for `PoseClassifier`. All distances are in hand sizes.
public struct PoseThresholds: Sendable, Hashable {
    /// Extension ratio above which a finger counts as extended.
    public var extended = 1.2
    /// Extension ratio below which a finger counts as curled.
    public var curled = 1.0
    /// Thumb–fingertip gap that starts a pinch.
    public var pinchEnter = 0.25
    /// Thumb–fingertip gap that ends a pinch (hysteresis).
    public var pinchExit = 0.38
    /// Minimum thumb-to-index-knuckle distance for an extended thumb.
    public var thumbOutFromIndex = 0.5
    /// Minimum thumb-to-little-knuckle distance for an extended thumb.
    public var thumbOutFromLittle = 1.0
    /// Index–middle spread below which two fingers count as "together".
    public var togetherSpread = 0.35
    /// Index–middle spread above which two fingers count as a V.
    public var peaceSpread = 0.5
    /// Index–little spread required for an open palm.
    public var palmFan = 0.9
    /// Thumb rise above the index knuckle required for thumbs-up.
    public var thumbsUpRise = 0.6
    /// Minimum mean landmark confidence to classify at all.
    public var minConfidence = 0.4

    /// Creates default thresholds.
    public init() {}

    /// Thresholds scaled by a user sensitivity in `0.5...1.5` (higher = more permissive pinches and spreads).
    public static func scaled(by sensitivity: Double) -> PoseThresholds {
        var t = PoseThresholds()
        let s = min(max(sensitivity, 0.5), 1.5)
        t.pinchEnter *= s
        t.pinchExit *= s
        t.palmFan /= s
        t.thumbsUpRise /= s
        return t
    }
}

/// Pure, rule-based single-frame hand shape classifier.
public struct PoseClassifier: Sendable {
    /// Thresholds in use.
    public var thresholds: PoseThresholds

    /// Creates a classifier.
    public init(thresholds: PoseThresholds = PoseThresholds()) {
        self.thresholds = thresholds
    }

    /// Classifies a pose. `previous` enables pinch hysteresis: an ongoing pinch stays a pinch until the gap exceeds `pinchExit`.
    public func classify(_ pose: HandPose, previous: HandShape = .unknown) -> HandShape {
        guard pose.meanConfidence >= thresholds.minConfidence else { return .unknown }
        let m = PoseMetrics(pose)
        let t = thresholds
        func isExtended(_ f: Finger) -> Bool { (m.fingerExtension[f] ?? 0) > t.extended }
        func isCurled(_ f: Finger) -> Bool { (m.fingerExtension[f] ?? 0) < t.curled }
        let thumbExtended = m.thumbToIndexMCP > t.thumbOutFromIndex && m.thumbToLittleMCP > t.thumbOutFromLittle

        let indexPinchLimit = (previous == .indexPinch || previous == .dial) ? t.pinchExit : t.pinchEnter
        let middlePinchLimit = previous == .middlePinch ? t.pinchExit : t.pinchEnter
        let indexPinched = m.thumbIndexGap < indexPinchLimit
        let middlePinched = m.thumbMiddleGap < middlePinchLimit

        if indexPinched {
            if isExtended(.middle) && isExtended(.ring) && isExtended(.little) { return .dial }
            return .indexPinch
        }
        // The middle finger must reach toward the thumb: a curled middle finger touching a tucked thumb is
        // just a pointing hand, not a right-click.
        if middlePinched && m.thumbIndexGap > t.pinchExit && isExtended(.index) && !isCurled(.middle) { return .middlePinch }

        let allCurled = Finger.allCases.allSatisfy(isCurled)
        if allCurled {
            if thumbExtended && m.thumbRise > t.thumbsUpRise { return .thumbsUp }
            if thumbExtended { return .thumbOut }
            return .fist
        }
        if Finger.allCases.allSatisfy(isExtended) {
            return (thumbExtended && m.fanSpread > t.palmFan) ? .openPalm : .unknown
        }
        if isExtended(.index) && isExtended(.middle) && isExtended(.ring) && isCurled(.little) { return .threeFingers }
        if isExtended(.index) && isExtended(.middle) && isCurled(.ring) && isCurled(.little) {
            if m.indexMiddleSpread < t.togetherSpread { return .twoFingers }
            if m.indexMiddleSpread > t.peaceSpread { return .peace }
            return .unknown
        }
        if isExtended(.index) && isCurled(.middle) && isCurled(.ring) && isCurled(.little) { return .pointing }
        return .unknown
    }
}
