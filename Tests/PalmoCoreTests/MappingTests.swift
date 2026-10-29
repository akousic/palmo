import Foundation
import Testing
@testable import PalmoCore

@Suite("Mapping and intent")
struct MappingTests {
    let keynote = AppContext(bundleID: "com.apple.iWork.Keynote", name: "Keynote")

    @Test("Global mappings resolve to actions")
    func globalMapping() {
        #expect(MappingResolver.resolve(.thumbsUp, app: .unknown, settings: .default) == .action(.playPause))
        #expect(MappingResolver.resolve(.palmFlip, app: .unknown, settings: .default) == .contextual)
    }

    @Test("Per-app overrides win over global mappings")
    func overrides() {
        var settings = PalmoSettings.default
        settings.appOverrides[keynote.bundleID] = [.swipeLeft: .nextSlide]
        #expect(MappingResolver.resolve(.swipeLeft, app: keynote, settings: settings) == .action(.nextSlide))
        #expect(MappingResolver.resolve(.swipeLeft, app: .unknown, settings: settings) == .action(.nextSpace))
    }

    @Test("Disabled, unmapped and fast-path gestures are ignored")
    func ignored() {
        var settings = PalmoSettings.default
        settings.enabledGestures.remove(.thumbsUp)
        settings.mappings[.swipeRight] = PalmoAction.none
        #expect(MappingResolver.resolve(.thumbsUp, app: .unknown, settings: settings) == .ignore)
        #expect(MappingResolver.resolve(.swipeRight, app: .unknown, settings: settings) == .ignore)
        #expect(MappingResolver.resolve(.pinchClick, app: .unknown, settings: settings) == .ignore)
    }

    @Test("Sanitizing clamps values and keeps arm/disarm enabled")
    func sanitize() {
        var settings = PalmoSettings.default
        settings.sensitivity = 9
        settings.enabledGestures = []
        let clean = settings.sanitized()
        #expect(clean.sensitivity == 1.5)
        #expect(clean.isEnabled(.arm) && clean.isEnabled(.disarm))
    }

    @Test("Settings survive a JSON round trip, including per-app overrides")
    func codable() throws {
        var settings = PalmoSettings.default
        settings.appOverrides[keynote.bundleID] = [.palmFlip: .startSlideshow]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(PalmoSettings.self, from: data) == settings)
    }

    @Test("Settings saved by an older version decode with new pointer defaults and keep custom mappings")
    func decodesOlderSettings() throws {
        var old = PalmoSettings.default
        old.mappings[.thumbsUp] = .missionControl
        old.cursorGain = 2.2
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        for key in ["pointerPrecision", "pointerAcceleration", "pointerSmoothing", "pointerAnchor", "snapToTargets", "snapRadius"] {
            json.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(PalmoSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.mappings[.thumbsUp] == .missionControl)
        #expect(decoded.cursorGain == 2.2)
        #expect(decoded.pointerPrecision == PalmoSettings.default.pointerPrecision)
        #expect(decoded.pointerAnchor == .knuckles)
        #expect(decoded.snapToTargets)
    }

    @Test("Smart gestures never resolve to closing or minimizing a window")
    func windowActionsNotContextual() {
        #expect(!PalmoAction.contextualCandidates.contains(.closeWindow))
        #expect(!PalmoAction.contextualCandidates.contains(.minimizeWindow))
        #expect(PalmoAction.mappable.contains(.closeWindow))
    }

    @Test("Rule-based context resolver knows common apps and has a default")
    func ruleContext() async throws {
        let resolver = RuleBasedContextResolver()
        #expect(try await resolver.resolve(gesture: .palmFlip, app: keynote) == .nextSlide)
        #expect(try await resolver.resolve(gesture: .palmFlip, app: AppContext(bundleID: "com.apple.Safari", name: "Safari")) == .browserReload)
        #expect(try await resolver.resolve(gesture: .palmFlip, app: .unknown) == .missionControl)
    }

    @Test("Natural-language rules parse common requests", arguments: [
        ("make thumbs up pause my music", Gesture.thumbsUp, PalmoAction.playPause, String?.none),
        ("Swipe left should go to the next slide in Keynote", .swipeLeft, .nextSlide, "Keynote"),
        ("palm flip = mute my mic when in Zoom", .palmFlip, .toggleMeetingMute, "Zoom"),
        ("set peace flick right to next track", .peaceFlickRight, .nextTrack, nil),
        ("three-finger up opens mission control", .threeFingerUp, .missionControl, nil),
        ("thumb flick left: previous app", .thumbFlickLeft, .appSwitcherPrevious, nil),
        ("make palm flip smart", .palmFlip, .contextual, nil),
        ("swipe right does nothing", .swipeRight, .none, nil),
        ("thumbs up closes the window", .thumbsUp, .closeWindow, nil),
        ("make thumb flick left close window", .thumbFlickLeft, .closeWindow, nil),
        ("swipe left should minimize the window", .swipeLeft, .minimizeWindow, nil),
    ])
    func parser(text: String, gesture: Gesture, action: PalmoAction, app: String?) throws {
        let change = try #require(RuleBasedMappingParser.parse(text))
        #expect(change == MappingChange(gesture: gesture, action: action, appName: app))
    }

    @Test("Unparseable requests return nil")
    func parserRejects() {
        #expect(RuleBasedMappingParser.parse("what's the weather") == nil)
        #expect(RuleBasedMappingParser.parse("thumbs up") == nil)
    }

    @Test("Applying a change writes a global mapping or an app override")
    func applying() {
        let global = PalmoSettings.default.applying(MappingChange(gesture: .thumbsUp, action: .toggleMute), bundleID: nil)
        #expect(global.mappings[.thumbsUp] == .toggleMute)
        let scoped = PalmoSettings.default.applying(MappingChange(gesture: .palmFlip, action: .startSlideshow, appName: "Keynote"),
                                                    bundleID: keynote.bundleID)
        #expect(scoped.appOverrides[keynote.bundleID]?[.palmFlip] == .startSlideshow)
        #expect(scoped.mappings[.palmFlip] == .contextual)
    }

    @Test("Rule-only configurator works without Apple Intelligence")
    func configuratorRules() async throws {
        let result = try #require(await MappingConfigurator(useAppleIntelligence: false).interpret("make thumbs up skip the song"))
        #expect(result.change.action == .nextTrack)
        #expect(result.source == .rules)
    }
}
