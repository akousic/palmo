import Foundation

/// Why Palmo disarmed.
public enum DisarmReason: String, Sendable, Codable {
    /// The user made the disarm gesture.
    case gesture
    /// No gesture was recognized for the idle timeout.
    case idle
    /// Disarmed from the menu, an App Intent, or a power event.
    case external
}

/// Output of the recognizer for one frame.
public enum GestureEvent: Sendable, Equatable {
    /// Palmo became armed.
    case armed
    /// Palmo became disarmed.
    case disarmed(DisarmReason)
    /// New absolute control-point position (normalized, user perspective) for relative cursor motion.
    case pointer(Point2D)
    /// Control-point position while the cursor should stay put: a pinch is forming, a click is
    /// settling, or a pinch is held but not yet dragging. The router tracks the hand without moving.
    case pointerHold(Point2D)
    /// Progress `0...1` of an open-palm hold toward arming (emitted while disarmed when it changes; 0 = lost).
    case armProgress(Double)
    /// A left click; `count` is 2 for a double-click.
    case click(count: Int)
    /// A right click.
    case rightClick
    /// Left button pressed for a drag.
    case dragBegan
    /// Control-point position during a drag.
    case dragMoved(Point2D)
    /// Left button released after a drag.
    case dragEnded
    /// Scroll displacement since the previous frame, in normalized units (positive dy = hand moved up).
    case scroll(dx: Double, dy: Double)
    /// Volume detents turned on the dial; positive = louder.
    case volumeStep(Int)
    /// A discrete, mappable gesture fired.
    case gesture(Gesture)
}

/// A motion classification produced by the optional Core ML model.
public struct MotionPrediction: Sendable, Hashable {
    /// Predicted gesture.
    public var gesture: Gesture
    /// Model confidence `0...1`.
    public var confidence: Double

    /// Creates a prediction.
    public init(gesture: Gesture, confidence: Double) {
        self.gesture = gesture
        self.confidence = confidence
    }
}

/// Per-frame context the recognizer needs besides the pose.
public struct RecognitionContext: Sendable, Hashable {
    /// Detected face rectangle, if any (hands overlapping it are ignored).
    public var faceRect: Rect2D?
    /// Seconds since the user last pressed a key.
    public var secondsSinceKeyboardInput: Double
    /// Latest motion-classifier output, if a model is installed.
    public var motionPrediction: MotionPrediction?

    /// Creates a context.
    public init(faceRect: Rect2D? = nil, secondsSinceKeyboardInput: Double = .infinity, motionPrediction: MotionPrediction? = nil) {
        self.faceRect = faceRect
        self.secondsSinceKeyboardInput = secondsSinceKeyboardInput
        self.motionPrediction = motionPrediction
    }
}

/// Timing and distance parameters for the recognizer, derived from `PalmoSettings`.
public struct RecognizerConfiguration: Sendable, Hashable {
    /// Gestures that may fire.
    public var enabled: Set<Gesture>
    /// Sensitivity `0.5...1.5`.
    public var sensitivity: Double
    /// Idle auto-disarm timeout.
    public var idleDisarm: TimeInterval
    /// Typing-guard window.
    public var typingGuard: TimeInterval
    /// Open-palm hold time needed to arm.
    public var armDwell: TimeInterval = 0.7
    /// Non-qualifying frames are tolerated this long during the arm hold before it restarts.
    public var armGrace: TimeInterval = 0.4
    /// Arm sensitivity `0.5...1.5`; higher accepts a less perfect open palm.
    public var armSensitivity: Double = 1.0
    /// Fist hold time needed to disarm.
    public var disarmDwell: TimeInterval = 1.0
    /// Hold time for static discrete poses (thumbs up).
    public var staticDwell: TimeInterval = 0.5
    /// A shape must persist this long before it becomes stable.
    public var shapeDebounce: TimeInterval = 0.1
    /// Pinches shorter than this are clicks; longer begin a drag.
    public var clickMaxDuration: TimeInterval = 0.3
    /// Two clicks within this window form a double-click.
    public var doubleClickWindow: TimeInterval = 0.4
    /// Motion window for swipes and flicks.
    public var motionWindow: TimeInterval = 0.45
    /// Window in which two palm-side changes form a palm flip.
    public var flipWindow: TimeInterval = 0.7
    /// Minimum confidence for accepting a Core ML motion prediction.
    public var minMotionConfidence: Double = 0.85
    /// Which part of the hand steers the pointer.
    public var pointerAnchor: PointerAnchor = .knuckles
    /// The cursor freezes once the thumb–index gap falls below `pinchExit × pinchApproach`.
    public var pinchApproach: Double = 1.35
    /// After a pinch is released, the cursor stays frozen this long so the release doesn't drag it.
    public var clickSettle: TimeInterval = 0.2

    /// Builds a configuration from settings.
    public init(settings: PalmoSettings) {
        let s = settings.sanitized()
        enabled = s.enabledGestures
        sensitivity = s.sensitivity
        idleDisarm = s.idleDisarmSeconds
        typingGuard = s.typingGuardSeconds
        pointerAnchor = s.pointerAnchor
        armSensitivity = s.armSensitivity
    }

    /// Cooldown after a discrete gesture fires.
    public func cooldown(for gesture: Gesture) -> TimeInterval {
        switch gesture {
        case .thumbsUp: 1.5
        case .palmFlip: 1.2
        case .threeFingerUp, .threeFingerDown: 1.0
        case .swipeLeft, .swipeRight, .peaceFlickLeft, .peaceFlickRight: 0.8
        case .thumbFlickLeft, .thumbFlickRight: 0.5
        case .middlePinch: 0.5
        default: 0.3
        }
    }
}

/// The gesture state machine: turns a stream of hand poses into `GestureEvent`s.
///
/// A pure value type with no I/O, so it is deterministic and unit-testable; the engine actor owns one instance.
public struct GestureRecognizer: Sendable {
    private struct Sample: Sendable {
        var time: TimeInterval
        var point: Point2D
        var shape: HandShape
    }

    /// Whether gestures other than arm are currently active.
    public private(set) var isArmed = false
    /// The current debounced hand shape.
    public private(set) var currentShape: HandShape = .unknown
    /// Active configuration.
    public var configuration: RecognizerConfiguration {
        didSet {
            classifier = PoseClassifier(thresholds: .scaled(by: configuration.sensitivity))
            armTest = .scaled(by: configuration.armSensitivity)
            armHold.dwell = configuration.armDwell
            armHold.grace = configuration.armGrace
        }
    }
    /// Progress `0...1` of the current arm hold.
    public var armProgress: Double { armHold.progress }
    /// Why the latest disarmed frame didn't count toward arming (`nil` if it did, or while armed).
    public private(set) var lastArmRejection: ArmRejection?
    /// The rejection that ended the most recent lost arm hold, with how far it got (for diagnostics).
    public private(set) var lastAbandonedArm: (reason: ArmRejection, progress: Double)?
    private var armTest: ArmPalmTest
    private var armHold: ArmAccumulator
    private var reportedArmProgress = 0.0

    private var classifier: PoseClassifier
    private var candidateShape: HandShape = .unknown
    private var candidateSince: TimeInterval = 0
    private var stableSince: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var cooldownUntil: [Gesture: TimeInterval] = [:]
    private var pinchStart: TimeInterval?
    private var settleUntil: TimeInterval = -.infinity
    private var dragging = false
    private var lastClickTime: TimeInterval = -.infinity
    private var lastScrollPoint: Point2D?
    private var dialReference: Double?
    private var history: [Sample] = []
    private var flipTimes: [TimeInterval] = []
    private var flipAnchor: Point2D?
    private var lastPalmSide: Int?
    private var lastTime: TimeInterval = 0

    /// Creates a recognizer.
    public init(configuration: RecognizerConfiguration) {
        self.configuration = configuration
        self.classifier = PoseClassifier(thresholds: .scaled(by: configuration.sensitivity))
        self.armTest = .scaled(by: configuration.armSensitivity)
        self.armHold = ArmAccumulator(dwell: configuration.armDwell, grace: configuration.armGrace)
    }

    /// Arms or disarms from outside (menu, App Intent, power events). Returns the resulting events.
    public mutating func setArmed(_ armed: Bool, at time: TimeInterval) -> [GestureEvent] {
        guard armed != isArmed else { return [] }
        if armed {
            isArmed = true
            armHold.reset()
            reportedArmProgress = 0
            lastArmRejection = nil
            lastActivity = time
            resetMotion()
            return [.armed]
        }
        return disarm(.external)
    }

    /// Processes one frame. Pass `nil` when no hand is visible.
    public mutating func process(_ pose: HandPose?, at time: TimeInterval, context: RecognitionContext) -> [GestureEvent] {
        lastTime = time
        var events: [GestureEvent] = []
        if isArmed && time - lastActivity > configuration.idleDisarm {
            return disarm(.idle)
        }
        guard let pose else {
            events += trackArm(nil, rejection: .noHand, at: time)
            events += endContinuous()
            candidateShape = .unknown
            currentShape = .unknown
            history.removeAll()
            flipTimes.removeAll()
            lastPalmSide = nil
            return events
        }
        // While disarmed only the face itself is excluded, since a raised palm often sits right beside it.
        if let face = context.faceRect, (isArmed ? face.insetBy(-0.03) : face).contains(pose.centroid) {
            events += trackArm(nil, rejection: .faceZone, at: time)
            events += endContinuous()
            currentShape = .unknown
            candidateShape = .unknown
            return events
        }

        let typing = context.secondsSinceKeyboardInput < configuration.typingGuard
        let emit = isArmed && !typing

        let raw = classifier.classify(pose, previous: currentShape)
        if raw != candidateShape {
            candidateShape = raw
            candidateSince = time
        }
        let debounce = (raw == .indexPinch || currentShape == .indexPinch) ? configuration.shapeDebounce * 0.6 : configuration.shapeDebounce
        if raw != currentShape && time - candidateSince >= debounce - 1e-9 {
            events += transition(from: currentShape, to: raw, at: time, emit: emit)
            currentShape = raw
            stableSince = time
        }

        guard isArmed else {
            let rejection: ArmRejection? = !configuration.enabled.contains(.arm) ? .disabled
                : typing ? .typing : armTest.evaluate(pose)
            events += trackArm(pose, rejection: rejection, at: time)
            if isArmed { stableSince = time }
            return events
        }
        if typing {
            events += endContinuous()
            return events
        }
        if currentShape == .fist && configuration.enabled.contains(.disarm) && time - stableSince >= configuration.disarmDwell {
            return events + disarm(.gesture)
        }

        events += continuous(pose, at: time)
        events += motion(pose, at: time, context: context)
        if !events.isEmpty { lastActivity = time }
        return events
    }

    // MARK: - Internals

    private mutating func transition(from old: HandShape, to new: HandShape, at time: TimeInterval, emit: Bool) -> [GestureEvent] {
        var events: [GestureEvent] = []
        if old == .indexPinch && new != .indexPinch {
            if dragging {
                events.append(.dragEnded)
                dragging = false
            } else if let start = pinchStart, time - start < configuration.clickMaxDuration,
                      emit, configuration.enabled.contains(.pinchClick) {
                let count = time - lastClickTime < configuration.doubleClickWindow ? 2 : 1
                lastClickTime = count == 2 ? -.infinity : time
                events.append(.click(count: count))
            }
            pinchStart = nil
            settleUntil = time + configuration.clickSettle
        }
        if new == .indexPinch { pinchStart = time }
        if new == .middlePinch { settleUntil = time + configuration.clickSettle }
        if new == .middlePinch && emit, let fired = fire(.middlePinch, at: time) {
            _ = fired
            events.append(.rightClick)
        }
        if new != .twoFingers { lastScrollPoint = nil }
        if new != .dial { dialReference = nil }
        return events
    }

    private mutating func continuous(_ pose: HandPose, at time: TimeInterval) -> [GestureEvent] {
        let enabled = configuration.enabled
        switch currentShape {
        case .pointing where enabled.contains(.point):
            let point = controlPoint(pose)
            let approaching = PoseMetrics(pose).thumbIndexGap < classifier.thresholds.pinchExit * configuration.pinchApproach
            return [approaching || time < settleUntil ? .pointerHold(point) : .pointer(point)]
        case .indexPinch:
            let point = controlPoint(pose)
            var events: [GestureEvent] = []
            if !dragging, enabled.contains(.pinchDrag), let start = pinchStart, time - start >= configuration.clickMaxDuration {
                dragging = true
                events.append(.dragBegan)
            }
            events.append(dragging ? .dragMoved(point) : .pointerHold(point))
            return events
        case .twoFingers where enabled.contains(.twoFingerScroll):
            let mid = Point2D.midpoint(pose[.indexTip], pose[.middleTip])
            defer { lastScrollPoint = mid }
            guard let last = lastScrollPoint else { return [] }
            let d = mid - last
            guard abs(d.x) + abs(d.y) > 0.002 else { return [] }
            return [.scroll(dx: d.x, dy: d.y)]
        case .dial where enabled.contains(.volumeDial):
            let angle = PoseMetrics(pose).rollAngle
            guard let reference = dialReference else {
                dialReference = angle
                return []
            }
            var delta = angle - reference
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            let step = (12.0 * .pi / 180) / configuration.sensitivity
            let detents = Int(delta / step)
            guard detents != 0 else { return [] }
            dialReference = reference + Double(detents) * step
            // Turning the hand clockwise from the user's view lowers the knuckle line's angle: treat as louder.
            return [.volumeStep(-detents)]
        default:
            return []
        }
    }

    private mutating func motion(_ pose: HandPose, at time: TimeInterval, context: RecognitionContext) -> [GestureEvent] {
        let centre = pose[.middleMCP]
        history.append(Sample(time: time, point: centre, shape: currentShape))
        history.removeAll { time - $0.time > 1.0 }

        if let prediction = context.motionPrediction, prediction.confidence >= configuration.minMotionConfidence,
           prediction.gesture.isRebindable, let g = fire(prediction.gesture, at: time) {
            return [.gesture(g)]
        }

        // Palm flip: two palm-side changes in a short window while the four fingers stay extended.
        let metrics = PoseMetrics(pose)
        let fingersOut = Finger.allCases.allSatisfy { (metrics.fingerExtension[$0] ?? 0) > classifier.thresholds.extended }
        if fingersOut {
            if let last = lastPalmSide, last != metrics.palmSide {
                if flipTimes.isEmpty { flipAnchor = centre }
                flipTimes.append(time)
            }
            lastPalmSide = metrics.palmSide
            flipTimes.removeAll { time - $0 > configuration.flipWindow }
            if flipTimes.count >= 2, let anchor = flipAnchor, anchor.distance(to: centre) < 0.12,
               let g = fire(.palmFlip, at: time) {
                return [.gesture(g)]
            }
        } else {
            lastPalmSide = nil
            flipTimes.removeAll()
        }

        if currentShape == .thumbsUp && time - stableSince >= configuration.staticDwell, let g = fire(.thumbsUp, at: time) {
            return [.gesture(g)]
        }

        let recent = history.filter { time - $0.time <= configuration.motionWindow && $0.shape == currentShape }
        guard recent.count >= 3, let first = recent.first, let last = recent.last else { return [] }
        let dx = last.point.x - first.point.x
        let dy = last.point.y - first.point.y
        let s = configuration.sensitivity
        let horizontal = abs(dx) > 2 * abs(dy)
        let vertical = abs(dy) > 2 * abs(dx)
        var candidate: Gesture?
        switch currentShape {
        case .openPalm where horizontal && abs(dx) > 0.22 / s:
            candidate = dx < 0 ? .swipeLeft : .swipeRight
        case .threeFingers where vertical && abs(dy) > 0.15 / s:
            candidate = dy > 0 ? .threeFingerUp : .threeFingerDown
        case .thumbOut where horizontal && abs(dx) > 0.12 / s:
            candidate = dx < 0 ? .thumbFlickLeft : .thumbFlickRight
        case .peace where horizontal && abs(dx) > 0.12 / s:
            candidate = dx < 0 ? .peaceFlickLeft : .peaceFlickRight
        default:
            candidate = nil
        }
        if let candidate, let g = fire(candidate, at: time) { return [.gesture(g)] }
        return []
    }

    private mutating func fire(_ gesture: Gesture, at time: TimeInterval) -> Gesture? {
        guard configuration.enabled.contains(gesture) else { return nil }
        if let until = cooldownUntil[gesture], time < until { return nil }
        cooldownUntil[gesture] = time + configuration.cooldown(for: gesture)
        if gesture != .middlePinch { resetMotion() }
        return gesture
    }

    /// Feeds the arm hold. Arms when it completes; emits progress for the overlay when it changes.
    private mutating func trackArm(_ pose: HandPose?, rejection: ArmRejection?, at time: TimeInterval) -> [GestureEvent] {
        guard !isArmed else { return [] }
        lastArmRejection = rejection
        var restarted = false
        let progressBefore = armHold.progress
        let complete = armHold.update(qualifies: rejection == nil, at: time, restarted: &restarted)
        if restarted { lastAbandonedArm = (rejection ?? .noHand, progressBefore) }
        if complete {
            isArmed = true
            lastActivity = time
            resetMotion()
            armHold.reset()
            reportedArmProgress = 0
            lastArmRejection = nil
            return [.armProgress(1), .armed]
        }
        let progress = armHold.progress
        if abs(progress - reportedArmProgress) >= 0.05 || (progress == 0 && reportedArmProgress > 0) {
            reportedArmProgress = progress
            return [.armProgress(progress)]
        }
        return []
    }

    /// The point that steers the cursor. The knuckle anchor sits on the index and middle knuckles,
    /// which stay still while the fingertips pinch.
    private func controlPoint(_ pose: HandPose) -> Point2D {
        switch configuration.pointerAnchor {
        case .knuckles: Point2D.midpoint(pose[.indexMCP], pose[.middleMCP])
        case .fingertip: pose[.indexTip]
        }
    }

    private mutating func resetMotion() {
        history.removeAll()
        flipTimes.removeAll()
        flipAnchor = nil
    }

    private mutating func endContinuous() -> [GestureEvent] {
        var events: [GestureEvent] = []
        if dragging {
            events.append(.dragEnded)
            dragging = false
        }
        pinchStart = nil
        lastScrollPoint = nil
        dialReference = nil
        return events
    }

    private mutating func disarm(_ reason: DisarmReason) -> [GestureEvent] {
        var events = endContinuous()
        isArmed = false
        armHold.reset()
        reportedArmProgress = 0
        resetMotion()
        lastPalmSide = nil
        events.append(.disarmed(reason))
        return events
    }
}
