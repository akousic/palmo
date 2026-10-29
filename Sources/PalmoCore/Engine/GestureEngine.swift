import Foundation
import os

/// A snapshot of the engine for the menu and overlay.
public struct EngineStatus: Sendable, Equatable {
    /// Whether gestures are armed.
    public var isArmed = false
    /// Whether a hand is currently visible.
    public var handVisible = false
    /// The current classified hand shape.
    public var shape: HandShape = .unknown
    /// The latest smoothed pose (for the overlay skeleton).
    public var pose: HandPose?
    /// The last thing the router did.
    public var lastOutcome: RoutedOutcome?
    /// Vision frames processed per second.
    public var framesPerSecond: Double = 0
    /// Current Vision frame-rate cap.
    public var targetFrameRate: Double = 30
    /// Progress `0...1` of an open-palm hold toward arming (0 when none is in progress).
    public var armProgress: Double = 0
    /// Why the latest frame didn't count toward arming, while disarmed with a hand in view.
    public var armRejection: ArmRejection?

    /// Creates an empty status.
    public init() {}
}

/// Owns the Tracking → Recognition → Intent pipeline. Consumes `HandFrame`s in order and emits status.
public actor GestureEngine {
    /// Status updates (newest only is buffered).
    public nonisolated let status: AsyncStream<EngineStatus>

    private let statusContinuation: AsyncStream<EngineStatus>.Continuation
    private let router: IntentRouter
    private let frontmost: FrontmostAppTracker
    private let keyboard: KeyboardActivity
    private let setFrameRate: @Sendable (Double) -> Void
    private var recognizer: GestureRecognizer
    private var smoother = HandPoseSmoother()
    private var classifier: MotionClassifier?
    private var poseWindow: [HandPose] = []
    private var lastClassification: TimeInterval = -.infinity
    private var pendingPrediction: (MotionPrediction, TimeInterval)?
    private var current = EngineStatus()
    private var lastHandTime: TimeInterval = -.infinity
    private var lastStatusEmit: TimeInterval = -.infinity
    private var frameTimes: [TimeInterval] = []
    private var lastFrameTime: TimeInterval = 0
    private var lastLoggedRejection: ArmRejection?
    private var lastRejectionLog: TimeInterval = -.infinity
    private var rejectionCounts: [ArmRejection: Int] = [:]

    /// Arming diagnostics. View with:
    /// `log stream --predicate 'subsystem == "com.kousic.palmo" && category == "arming"' --level debug`
    /// Only reasons and timing are logged, never images or hand coordinates.
    static let armLog = Logger(subsystem: "com.kousic.palmo", category: "arming")

    /// Creates an engine.
    /// - Parameter setFrameRate: called when the engine wants the capture layer to change its Vision fps cap.
    public init(settings: PalmoSettings,
                router: IntentRouter,
                frontmost: FrontmostAppTracker,
                keyboard: KeyboardActivity,
                setFrameRate: @escaping @Sendable (Double) -> Void) {
        var c: AsyncStream<EngineStatus>.Continuation!
        status = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { c = $0 }
        statusContinuation = c
        self.router = router
        self.frontmost = frontmost
        self.keyboard = keyboard
        self.setFrameRate = setFrameRate
        recognizer = GestureRecognizer(configuration: RecognizerConfiguration(settings: settings.sanitized()))
    }

    /// Processes frames until the stream ends or the task is cancelled.
    public func run(frames: AsyncStream<HandFrame>) async {
        for await frame in frames {
            if Task.isCancelled { break }
            await ingest(frame)
        }
    }

    /// Applies new settings to recognition and routing.
    public func update(settings: PalmoSettings) async {
        let clean = settings.sanitized()
        recognizer.configuration = RecognizerConfiguration(settings: clean)
        await router.update(settings: clean)
    }

    /// Installs or removes the optional Core ML motion classifier.
    public func setMotionClassifier(_ classifier: MotionClassifier?) {
        self.classifier = classifier
        poseWindow.removeAll()
    }

    /// Arms or disarms from the menu, a shortcut or an App Intent.
    public func setArmed(_ armed: Bool) async {
        let events = recognizer.setArmed(armed, at: lastFrameTime)
        await dispatch(events, at: lastFrameTime)
        current.isArmed = recognizer.isArmed
        updateFrameRate(at: lastFrameTime)
        statusContinuation.yield(current)
    }

    /// Whether gestures are armed.
    public var isArmed: Bool { recognizer.isArmed }

    /// Processes one frame.
    public func ingest(_ frame: HandFrame) async {
        let t = frame.timestamp
        lastFrameTime = t
        var pose: HandPose?
        if let raw = frame.pose {
            pose = smoother.smooth(raw)
            lastHandTime = t
        } else {
            smoother.reset()
        }

        if let pose, let classifier, recognizer.isArmed {
            poseWindow.append(pose)
            if poseWindow.count > classifier.windowSize { poseWindow.removeFirst(poseWindow.count - classifier.windowSize) }
            if poseWindow.count == classifier.windowSize, t - lastClassification >= 0.5 {
                lastClassification = t
                if let prediction = try? await classifier.predict(poseWindow) {
                    pendingPrediction = (prediction, t)
                }
            }
        } else if pose == nil {
            poseWindow.removeAll()
        }

        var prediction: MotionPrediction?
        if let (p, at) = pendingPrediction, t - at < 0.3 {
            prediction = p
            pendingPrediction = nil
        }
        let context = RecognitionContext(faceRect: frame.face,
                                         secondsSinceKeyboardInput: keyboard.secondsSinceUserKey,
                                         motionPrediction: prediction)
        let wasArmed = recognizer.isArmed
        let abandonedBefore = recognizer.lastAbandonedArm.map { "\($0.reason)\($0.progress)" }
        let events = recognizer.process(pose, at: t, context: context)
        await dispatch(events, at: t)
        logArming(wasArmed: wasArmed, abandonedBefore: abandonedBefore, events: events, at: t)
        for case .armProgress(let p) in events { current.armProgress = p }
        if recognizer.isArmed { current.armProgress = 0 }
        current.armRejection = (recognizer.isArmed || pose == nil) ? nil : recognizer.lastArmRejection

        frameTimes.append(t)
        frameTimes.removeAll { t - $0 > 1 }
        current.isArmed = recognizer.isArmed
        current.handVisible = pose != nil
        current.shape = recognizer.currentShape
        current.pose = pose
        current.framesPerSecond = Double(frameTimes.count)
        updateFrameRate(at: t)
        if t - lastStatusEmit >= 1.0 / 15 || !events.isEmpty {
            lastStatusEmit = t
            statusContinuation.yield(current)
        }
    }

    private func dispatch(_ events: [GestureEvent], at t: TimeInterval) async {
        for event in events {
            let app = frontmost.current
            if case .gesture = event {
                // Discrete gestures may consult the language model; never stall the frame loop on them.
                Task { [router] in
                    let outcome = await router.handle(event, at: t, app: app)
                    self.record(outcome)
                }
            } else if let outcome = await router.handle(event, at: t, app: app) {
                record(outcome)
            }
        }
    }

    private func record(_ outcome: RoutedOutcome?) {
        guard let outcome else { return }
        if case .armState = outcome {} else { current.lastOutcome = outcome }
        statusContinuation.yield(current)
    }

    private func logArming(wasArmed: Bool, abandonedBefore: String?, events: [GestureEvent], at t: TimeInterval) {
        let log = Self.armLog
        if !wasArmed && recognizer.isArmed {
            log.info("Armed by open-palm hold")
            rejectionCounts.removeAll()
            lastLoggedRejection = nil
            return
        }
        guard !recognizer.isArmed else { return }
        if let abandoned = recognizer.lastAbandonedArm, "\(abandoned.reason)\(abandoned.progress)" != abandonedBefore {
            let counts = rejectionCounts.sorted { $0.value > $1.value }.map { "\($0.key.rawValue)=\($0.value)" }.joined(separator: " ")
            log.notice("Arm hold lost at \(Int(abandoned.progress * 100), privacy: .public)%: \(abandoned.reason.explanation, privacy: .public). Recent rejections: \(counts, privacy: .public)")
            rejectionCounts.removeAll()
        }
        guard let reason = recognizer.lastArmRejection, reason != .noHand else { return }
        rejectionCounts[reason, default: 0] += 1
        // Log a change of reason immediately, otherwise at most every 2 s.
        if reason != lastLoggedRejection || t - lastRejectionLog > 2 {
            lastLoggedRejection = reason
            lastRejectionLog = t
            log.debug("Arm frame rejected: \(reason.explanation, privacy: .public)")
        }
    }

    /// Idle throttling: 30 fps while armed or while a hand is in view (so the arm hold builds quickly),
    /// 8 fps when nobody is gesturing.
    private func updateFrameRate(at t: TimeInterval) {
        let target: Double = recognizer.isArmed ? 30 : (t - lastHandTime < 3 ? 30 : 8)
        if target != current.targetFrameRate {
            current.targetFrameRate = target
            setFrameRate(target)
        }
    }
}
