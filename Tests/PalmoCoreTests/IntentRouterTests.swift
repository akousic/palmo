import Foundation
import Testing
@testable import PalmoCore

/// Records synthesized input instead of posting events.
actor MockSynthesizer: InputSynthesizing {
    enum Call: Equatable {
        case move(Double, Double, Bool), click(Int), rightClick, down, up, scroll(Int, Int), volume(Int), perform(PalmoAction)
    }
    private(set) var calls: [Call] = []
    var failPerform = false
    var target: ScreenRect?
    func setTarget(_ value: ScreenRect?) { target = value }
    func clickableFrame(near point: ScreenPoint, radius: Double) async -> ScreenRect? { target }
    func setFailPerform(_ value: Bool) { failPerform = value }
    func cursorPosition() async -> ScreenPoint { ScreenPoint(x: 500, y: 400) }
    func screenBounds() async -> ScreenRect { ScreenRect(minX: 0, minY: 0, maxX: 1000, maxY: 800) }
    func moveCursor(to point: ScreenPoint, dragging: Bool) async { calls.append(.move(point.x, point.y, dragging)) }
    func click(count: Int) async { calls.append(.click(count)) }
    func rightClick() async { calls.append(.rightClick) }
    func mouseDown() async { calls.append(.down) }
    func mouseUp() async { calls.append(.up) }
    func scroll(dx: Int, dy: Int) async { calls.append(.scroll(dx, dy)) }
    func volume(steps: Int) async { calls.append(.volume(steps)) }
    func perform(_ action: PalmoAction, app: AppContext) async throws {
        if failPerform { throw ActionExecutionError.accessibilityNotGranted }
        calls.append(.perform(action))
    }
}

/// A context resolver with a fixed answer and optional delay.
final class StubResolver: ContextResolver, @unchecked Sendable {
    let answer: PalmoAction?
    let delay: Double
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    init(_ answer: PalmoAction?, delay: Double = 0) { self.answer = answer; self.delay = delay }
    func resolve(gesture: Gesture, app: AppContext) async throws -> PalmoAction? {
        lock.withLock { _count += 1 }
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        return answer
    }
}

@Suite("Intent router")
struct IntentRouterTests {
    let app = AppContext(bundleID: "com.example.app", name: "Example")

    @Test("Fast-path events never consult a resolver")
    func fastPath() async {
        let synth = MockSynthesizer()
        let model = StubResolver(.missionControl)
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: model)
        #expect(await router.handle(.click(count: 2), at: 0, app: app) == .fastPath("Double-click"))
        await router.handle(.rightClick, at: 0, app: app)
        await router.handle(.volumeStep(-1), at: 0, app: app)
        #expect(await synth.calls == [.click(2), .rightClick, .volume(-1)])
        #expect(model.count == 0)
    }

    @Test("Scrolling up with the hand scrolls content down (natural direction)")
    func scrollSign() async {
        let synth = MockSynthesizer()
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        await router.handle(.scroll(dx: 0, dy: 0.01), at: 0, app: app)
        #expect(await synth.calls == [.scroll(0, -24)])
    }

    @Test("Disarming mid-drag releases the mouse")
    func disarmReleases() async {
        let synth = MockSynthesizer()
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        await router.handle(.dragBegan, at: 0, app: app)
        #expect(await router.handle(.disarmed(.idle), at: 1, app: app) == .armState(false))
        #expect(await synth.calls == [.down, .up])
    }

    @Test("Pointer motion moves the cursor after the anchor frame")
    func pointer() async {
        let synth = MockSynthesizer()
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        await router.handle(.pointer(Point2D(x: 0.5, y: 0.5)), at: 0, app: app)
        await router.handle(.pointer(Point2D(x: 0.53, y: 0.5)), at: 1.0 / 30, app: app)
        let calls = await synth.calls
        #expect(calls.count == 1)
        if case .move(let x, _, false) = calls.first { #expect(x > 500) } else { Issue.record("expected a move") }
    }

    @Test("A held pointer re-anchors without moving the cursor")
    func pointerHold() async {
        let synth = MockSynthesizer()
        var settings = PalmoSettings.default
        settings.pointerSmoothing = 0
        let router = IntentRouter(settings: settings, synthesizer: synth, modelResolver: nil)
        await router.handle(.pointer(Point2D(x: 0.5, y: 0.5)), at: 0, app: app)
        await router.handle(.pointerHold(Point2D(x: 0.6, y: 0.5)), at: 1.0 / 30, app: app)
        #expect(await synth.calls.isEmpty)
        await router.handle(.pointer(Point2D(x: 0.601, y: 0.5)), at: 2.0 / 30, app: app)
        let calls = await synth.calls
        if case .move(let x, _, false) = calls.first { #expect(x - 500 < 5) } else { Issue.record("expected a small move") }
    }

    @Test("A click just outside a small button snaps onto its center first")
    func snapsClick() async {
        let synth = MockSynthesizer()
        await synth.setTarget(ScreenRect(minX: 505, minY: 395, maxX: 519, maxY: 409))
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        await router.handle(.click(count: 1), at: 0, app: app)
        #expect(await synth.calls == [.move(512, 402, false), .click(1)])
    }

    @Test("Snapping is skipped when the cursor is already on the target or snapping is off")
    func noSnap() async {
        let synth = MockSynthesizer()
        await synth.setTarget(ScreenRect(minX: 490, minY: 390, maxX: 520, maxY: 410))
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        await router.handle(.click(count: 1), at: 0, app: app)
        var off = PalmoSettings.default
        off.snapToTargets = false
        await synth.setTarget(ScreenRect(minX: 505, minY: 395, maxX: 519, maxY: 409))
        await router.update(settings: off)
        await router.handle(.rightClick, at: 1, app: app)
        #expect(await synth.calls == [.click(1), .rightClick])
    }

    @Test("Mapped gestures execute their action")
    func mapped() async {
        let synth = MockSynthesizer()
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        #expect(await router.route(.thumbsUp, app: app) == .action(.playPause, gesture: .thumbsUp, source: .mapping))
        #expect(await synth.calls == [.perform(.playPause)])
    }

    @Test("Execution failures are reported, not thrown")
    func failure() async {
        let synth = MockSynthesizer()
        await synth.setFailPerform(true)
        let router = IntentRouter(settings: .default, synthesizer: synth, modelResolver: nil)
        if case .failed(.thumbsUp, _) = await router.route(.thumbsUp, app: app) {} else { Issue.record("expected failure") }
    }

    @Test("Smart gestures use the model, then the cache")
    func modelThenCache() async {
        let model = StubResolver(.nextSlide)
        let router = IntentRouter(settings: .default, synthesizer: MockSynthesizer(), modelResolver: model)
        #expect(await router.route(.palmFlip, app: app) == .action(.nextSlide, gesture: .palmFlip, source: .appleIntelligence))
        #expect(await router.route(.palmFlip, app: app) == .action(.nextSlide, gesture: .palmFlip, source: .cache))
        #expect(model.count == 1)
        await router.clearCache()
        _ = await router.route(.palmFlip, app: app)
        #expect(model.count == 2)
    }

    @Test("A slow model times out to the rule fallback")
    func timeout() async {
        let router = IntentRouter(settings: .default, synthesizer: MockSynthesizer(),
                                  modelResolver: StubResolver(.nextSlide, delay: 5),
                                  fallbackResolver: StubResolver(.missionControl), modelTimeout: 0.1)
        let start = Date()
        #expect(await router.route(.palmFlip, app: app) == .action(.missionControl, gesture: .palmFlip, source: .rules))
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test("Rule results are not cached, and Apple Intelligence can be turned off")
    func rulesOnly() async {
        var settings = PalmoSettings.default
        settings.useAppleIntelligence = false
        let model = StubResolver(.nextSlide)
        let router = IntentRouter(settings: settings, synthesizer: MockSynthesizer(), modelResolver: model,
                                  fallbackResolver: StubResolver(.missionControl))
        #expect(await router.route(.palmFlip, app: app) == .action(.missionControl, gesture: .palmFlip, source: .rules))
        #expect(await router.route(.palmFlip, app: app) == .action(.missionControl, gesture: .palmFlip, source: .rules))
        #expect(model.count == 0)
    }

    @Test("withTimeout returns quickly with nil for slow work and the value for fast work")
    func withTimeoutBehaviour() async {
        let slow: Int? = await withTimeout(seconds: 0.05) { try? await Task.sleep(for: .seconds(3)); return 1 }
        let fast: Int? = await withTimeout(seconds: 1) { 2 }
        #expect(slow == nil)
        #expect(fast == 2)
    }
}
