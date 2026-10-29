import Foundation

/// Where a routed action came from.
public enum ResolutionSource: String, Sendable, Codable {
    /// The user's mapping or a per-app override.
    case mapping
    /// Apple Intelligence (Foundation Models).
    case appleIntelligence
    /// The rule-based fallback.
    case rules
    /// A cached earlier resolution for the same app.
    case cache
}

/// What the router did with an event, for the overlay and menu.
public enum RoutedOutcome: Sendable, Equatable {
    /// A fast-path input event was synthesized (description for display).
    case fastPath(String)
    /// A high-level action ran.
    case action(PalmoAction, gesture: Gesture, source: ResolutionSource)
    /// A gesture was recognized but mapped to nothing.
    case ignored(Gesture)
    /// Executing an action failed.
    case failed(Gesture, String)
    /// Armed state changed.
    case armState(Bool)
}

/// The Intent layer: routes recognizer events to the fast path, the mapping, or context resolution.
///
/// Cursor, click, drag, scroll and volume never touch the language model. Only the `.contextual`
/// mapping goes to Foundation Models, with a hard timeout and a rule-based fallback.
public actor IntentRouter {
    private var settings: PalmoSettings
    private var mapper: CursorMapper
    private let synthesizer: any InputSynthesizing
    private let modelResolver: (any ContextResolver)?
    private let fallbackResolver: any ContextResolver
    private let modelTimeout: Double
    private var cache: [String: PalmoAction] = [:]
    private var dragging = false

    /// Pixels of scroll per normalized unit of hand motion.
    public static let scrollScale = 2400.0

    /// Creates a router.
    public init(settings: PalmoSettings,
                synthesizer: any InputSynthesizing,
                modelResolver: (any ContextResolver)?,
                fallbackResolver: any ContextResolver = RuleBasedContextResolver(),
                modelTimeout: Double = 1.5) {
        self.settings = settings.sanitized()
        var mapper = CursorMapper()
        mapper.configure(with: settings)
        self.mapper = mapper
        self.synthesizer = synthesizer
        self.modelResolver = modelResolver
        self.fallbackResolver = fallbackResolver
        self.modelTimeout = modelTimeout
    }

    /// Applies new settings and clears the context cache.
    public func update(settings newSettings: PalmoSettings) {
        settings = newSettings.sanitized()
        mapper.configure(with: settings)
        cache.removeAll()
    }

    /// Clears cached smart-gesture resolutions.
    public func clearCache() {
        cache.removeAll()
    }

    /// Handles one event. `time` is the frame timestamp in seconds.
    @discardableResult
    public func handle(_ event: GestureEvent, at time: TimeInterval, app: AppContext) async -> RoutedOutcome? {
        switch event {
        case .armed:
            mapper.reset()
            return .armState(true)
        case .disarmed:
            if dragging {
                dragging = false
                await synthesizer.mouseUp()
            }
            mapper.reset()
            return .armState(false)
        case .pointer(let p):
            await moveCursor(p, at: time, dragging: false)
            return nil
        case .armProgress:
            return nil
        case .pointerHold(let p):
            mapper.hold(handPoint: p, at: time)
            return nil
        case .click(let count):
            mapper.reset()
            await snapToTarget()
            await synthesizer.click(count: count)
            return .fastPath(count == 2 ? "Double-click" : "Click")
        case .rightClick:
            mapper.reset()
            await snapToTarget()
            await synthesizer.rightClick()
            return .fastPath("Right-click")
        case .dragBegan:
            mapper.reset()
            dragging = true
            await synthesizer.mouseDown()
            return .fastPath("Drag")
        case .dragMoved(let p):
            await moveCursor(p, at: time, dragging: true)
            return nil
        case .dragEnded:
            dragging = false
            mapper.reset()
            await synthesizer.mouseUp()
            return .fastPath("Drop")
        case .scroll(let dx, let dy):
            let s = settings.sensitivity
            // Content follows the hand, like natural trackpad scrolling.
            await synthesizer.scroll(dx: Int((dx * Self.scrollScale * s).rounded()),
                                     dy: Int((-dy * Self.scrollScale * s).rounded()))
            return nil
        case .volumeStep(let steps):
            await synthesizer.volume(steps: steps)
            return .fastPath(steps > 0 ? "Volume up" : "Volume down")
        case .gesture(let gesture):
            return await route(gesture, app: app)
        }
    }

    /// Resolves and executes a discrete gesture.
    public func route(_ gesture: Gesture, app: AppContext) async -> RoutedOutcome {
        let action: PalmoAction
        let source: ResolutionSource
        switch MappingResolver.resolve(gesture, app: app, settings: settings) {
        case .ignore:
            return .ignored(gesture)
        case .action(let a):
            action = a
            source = .mapping
        case .contextual:
            guard let resolved = await resolveContextual(gesture, app: app) else { return .ignored(gesture) }
            (action, source) = resolved
        }
        do {
            try await synthesizer.perform(action, app: app)
            return .action(action, gesture: gesture, source: source)
        } catch {
            return .failed(gesture, error.localizedDescription)
        }
    }

    /// Picks the action for a contextual gesture: cache → Apple Intelligence (with timeout) → rules.
    public func resolveContextual(_ gesture: Gesture, app: AppContext) async -> (PalmoAction, ResolutionSource)? {
        let key = "\(gesture.rawValue)|\(app.bundleID)"
        if let cached = cache[key] { return (cached, .cache) }
        if settings.useAppleIntelligence, let modelResolver {
            let fromModel: PalmoAction? = await withTimeout(seconds: modelTimeout) {
                try? await modelResolver.resolve(gesture: gesture, app: app)
            }
            if let fromModel {
                cache[key] = fromModel
                return (fromModel, .appleIntelligence)
            }
        }
        guard let fallback = try? await fallbackResolver.resolve(gesture: gesture, app: app) else { return nil }
        return (fallback, .rules)
    }

    /// If the cursor is just off a small control, moves it onto the control's center before clicking.
    private func snapToTarget() async {
        guard settings.snapToTargets else { return }
        let cursor = await synthesizer.cursorPosition()
        guard let frame = await synthesizer.clickableFrame(near: cursor, radius: settings.snapRadius),
              !frame.contains(x: cursor.x, y: cursor.y) else { return }
        await synthesizer.moveCursor(to: ScreenPoint(x: frame.midX, y: frame.midY), dragging: false)
    }

    private func moveCursor(_ p: Point2D, at time: TimeInterval, dragging: Bool) async {
        let cursor = await synthesizer.cursorPosition()
        let bounds = await synthesizer.screenBounds()
        guard let next = mapper.update(handPoint: p, at: time, cursor: (cursor.x, cursor.y), bounds: bounds) else { return }
        await synthesizer.moveCursor(to: ScreenPoint(x: next.x, y: next.y), dragging: dragging)
    }
}
