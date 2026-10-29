import Foundation

/// Why a frame did not count toward arming. Logged (without any image or coordinates) to diagnose arming.
public enum ArmRejection: String, Sendable, Codable, CaseIterable {
    /// No hand in view.
    case noHand
    /// The hand overlapped the detected face.
    case faceZone
    /// A key was pressed recently (typing guard).
    case typing
    /// Vision's landmark confidence was too low.
    case lowConfidence
    /// One or more fingers were not straight enough.
    case fingersNotExtended
    /// The thumb was tucked against the palm.
    case thumbTucked
    /// The fingers were held together rather than spread.
    case fingersTogether
    /// The arm gesture is turned off.
    case disabled

    /// Plain-English explanation.
    public var explanation: String {
        switch self {
        case .noHand: "no hand in view"
        case .faceZone: "hand in front of the face"
        case .typing: "typing guard (key pressed recently)"
        case .lowConfidence: "hand tracking confidence low (lighting or partly out of frame)"
        case .fingersNotExtended: "fingers not straight"
        case .thumbTucked: "thumb tucked in"
        case .fingersTogether: "fingers not spread"
        case .disabled: "arm gesture disabled"
        }
    }
}

/// A lenient open-palm test used only for arming. It is looser than `PoseClassifier`'s `.openPalm`
/// because arming happens at a low frame rate with the hand often raised at an angle.
public struct ArmPalmTest: Sendable, Hashable {
    /// Minimum mean landmark confidence.
    public var minConfidence = 0.3
    /// Extension ratio the index, middle and ring fingers must exceed.
    public var extended = 1.12
    /// Extension ratio the little finger must exceed (it's short and often reads as bent).
    public var littleExtended = 1.0
    /// Minimum thumb-to-index-knuckle distance, in hand sizes.
    public var thumbOut = 0.35
    /// Minimum index-to-little tip spread, in hand sizes.
    public var fan = 0.55

    /// Creates the default test.
    public init() {}

    /// The test scaled by an arm sensitivity in `0.5...1.5` (higher is easier to arm).
    public static func scaled(by sensitivity: Double) -> ArmPalmTest {
        var t = ArmPalmTest()
        let s = min(max(sensitivity, 0.5), 1.5)
        t.extended = 1 + (t.extended - 1) / s
        t.littleExtended = 1 + (t.littleExtended - 1) / s - (s - 1) * 0.15
        t.thumbOut /= s
        t.fan /= s
        t.minConfidence = min(max(t.minConfidence / s, 0.15), 0.6)
        return t
    }

    /// Returns `nil` if the pose counts as an open palm for arming, or the first reason it doesn't.
    public func evaluate(_ pose: HandPose) -> ArmRejection? {
        guard pose.meanConfidence >= minConfidence else { return .lowConfidence }
        let m = PoseMetrics(pose)
        for finger in [Finger.index, .middle, .ring] where (m.fingerExtension[finger] ?? 0) <= extended {
            return .fingersNotExtended
        }
        if (m.fingerExtension[.little] ?? 0) <= littleExtended { return .fingersNotExtended }
        if m.thumbToIndexMCP <= thumbOut { return .thumbTucked }
        if m.fanSpread <= fan { return .fingersTogether }
        return nil
    }
}

/// Accumulates open-palm time toward arming, tolerating brief dropouts.
///
/// Each qualifying frame adds the time since the previous frame (capped, so a stalled camera can't arm
/// in one step). Frames that don't qualify pause the hold instead of restarting it; only a gap longer
/// than `grace` since the last qualifying frame starts over.
public struct ArmAccumulator: Sendable, Hashable {
    /// Open-palm time needed to arm.
    public var dwell: TimeInterval
    /// How long non-qualifying frames are tolerated before the hold restarts.
    public var grace: TimeInterval
    /// Minimum qualifying frames before arming, so one lucky frame at a low frame rate can't arm.
    public var minFrames: Int
    /// Largest step a single frame can add.
    public var maxStep: TimeInterval = 0.2

    /// Accumulated open-palm time.
    public private(set) var held: TimeInterval = 0
    /// Qualifying frames in the current hold.
    public private(set) var frames = 0
    private var lastHit: TimeInterval?
    private var lastFrame: TimeInterval?

    /// Creates an accumulator.
    public init(dwell: TimeInterval = 0.7, grace: TimeInterval = 0.4, minFrames: Int = 4) {
        self.dwell = dwell
        self.grace = grace
        self.minFrames = minFrames
    }

    /// Progress `0...1` toward arming.
    public var progress: Double { dwell > 0 ? min(held / dwell, 1) : 1 }

    /// Feeds one frame. Returns `true` when the hold completes. `restarted` is set when an in-progress hold is lost.
    public mutating func update(qualifies: Bool, at time: TimeInterval, restarted: inout Bool) -> Bool {
        restarted = false
        let step = lastFrame.map { min(max(time - $0, 0), maxStep) } ?? 0
        lastFrame = time
        if qualifies {
            if let lastHit, time - lastHit > grace {
                restarted = held > 0
                reset(keepingFrameTime: true)
            }
            if frames > 0 { held += step }
            frames += 1
            lastHit = time
            return held >= dwell - 1e-9 && frames >= minFrames
        }
        if let lastHit, time - lastHit > grace, held > 0 || frames > 0 {
            restarted = held > 0
            reset(keepingFrameTime: true)
        }
        return false
    }

    /// Clears the hold.
    public mutating func reset(keepingFrameTime: Bool = false) {
        held = 0
        frames = 0
        lastHit = nil
        if !keepingFrameTime { lastFrame = nil }
    }
}
