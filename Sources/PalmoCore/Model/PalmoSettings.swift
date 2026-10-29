import Foundation

/// The frontmost application, used for per-app overrides and context resolution.
public struct AppContext: Sendable, Hashable, Codable {
    /// Bundle identifier, e.g. `com.apple.Safari`.
    public var bundleID: String
    /// Localized display name.
    public var name: String

    /// Creates an app context.
    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }

    /// Placeholder used when no frontmost app is known.
    public static let unknown = AppContext(bundleID: "", name: "Unknown")
}

/// All user-configurable settings. A plain value type persisted as JSON.
public struct PalmoSettings: Sendable, Hashable, Codable {
    /// Gestures that are currently enabled.
    public var enabledGestures: Set<Gesture>
    /// Detection sensitivity, `0.5...1.5`; higher means easier to trigger.
    public var sensitivity: Double
    /// Cursor speed multiplier, `0.5...3`.
    public var cursorGain: Double
    /// Global gesture → action mapping for rebindable gestures.
    public var mappings: [Gesture: PalmoAction]
    /// Per-app overrides keyed by bundle identifier.
    public var appOverrides: [String: [Gesture: PalmoAction]]
    /// Display names for overridden apps, keyed by bundle identifier.
    public var appNames: [String: String]
    /// Whether to use Apple Intelligence (Foundation Models) when available.
    public var useAppleIntelligence: Bool
    /// Whether to show the floating feedback overlay.
    public var showOverlay: Bool
    /// Seconds without a recognized gesture before auto-disarm.
    public var idleDisarmSeconds: Double
    /// Seconds after a key press during which gestures are suppressed.
    public var typingGuardSeconds: Double
    /// Whether to pause the camera while Low Power Mode is on.
    public var pauseOnLowPower: Bool
    /// Whether onboarding has been completed.
    public var hasCompletedOnboarding: Bool
    /// Pointer speed at slow hand speeds, as a fraction of normal, `0.15...1`. Lower means finer control.
    public var pointerPrecision: Double
    /// Extra pointer speed for fast hand motion, `0...4`. Higher means a quick flick travels further.
    public var pointerAcceleration: Double
    /// Pointer smoothing, `0...1`. Higher removes more jitter when the hand is nearly still, with a little more lag.
    public var pointerSmoothing: Double
    /// Which part of the hand steers the pointer.
    public var pointerAnchor: PointerAnchor
    /// Whether clicks snap to a nearby button, using Accessibility hit-testing.
    public var snapToTargets: Bool
    /// Snap radius in points for clicks.
    public var snapRadius: Double

    /// Creates settings.
    public init(enabledGestures: Set<Gesture> = Set(Gesture.allCases),
                sensitivity: Double = 1.0,
                cursorGain: Double = 1.4,
                mappings: [Gesture: PalmoAction] = PalmoSettings.defaultMappings,
                appOverrides: [String: [Gesture: PalmoAction]] = [:],
                appNames: [String: String] = [:],
                useAppleIntelligence: Bool = true,
                showOverlay: Bool = true,
                idleDisarmSeconds: Double = 20,
                typingGuardSeconds: Double = 0.6,
                pauseOnLowPower: Bool = true,
                hasCompletedOnboarding: Bool = false,
                pointerPrecision: Double = 0.35,
                pointerAcceleration: Double = 1.6,
                pointerSmoothing: Double = 0.5,
                pointerAnchor: PointerAnchor = .knuckles,
                snapToTargets: Bool = true,
                snapRadius: Double = 14) {
        self.enabledGestures = enabledGestures
        self.sensitivity = sensitivity
        self.cursorGain = cursorGain
        self.mappings = mappings
        self.appOverrides = appOverrides
        self.appNames = appNames
        self.useAppleIntelligence = useAppleIntelligence
        self.showOverlay = showOverlay
        self.idleDisarmSeconds = idleDisarmSeconds
        self.typingGuardSeconds = typingGuardSeconds
        self.pauseOnLowPower = pauseOnLowPower
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.pointerPrecision = pointerPrecision
        self.pointerAcceleration = pointerAcceleration
        self.pointerSmoothing = pointerSmoothing
        self.pointerAnchor = pointerAnchor
        self.snapToTargets = snapToTargets
        self.snapRadius = snapRadius
    }

    private enum CodingKeys: String, CodingKey {
        case enabledGestures, sensitivity, cursorGain, mappings, appOverrides, appNames, useAppleIntelligence
        case showOverlay, idleDisarmSeconds, typingGuardSeconds, pauseOnLowPower, hasCompletedOnboarding
        case pointerPrecision, pointerAcceleration, pointerSmoothing, pointerAnchor, snapToTargets, snapRadius
    }

    /// Decodes settings, filling in defaults for any key missing from older saved versions,
    /// so upgrading never resets the user's mappings.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PalmoSettings.default
        enabledGestures = try c.decodeIfPresent(Set<Gesture>.self, forKey: .enabledGestures) ?? d.enabledGestures
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        cursorGain = try c.decodeIfPresent(Double.self, forKey: .cursorGain) ?? d.cursorGain
        mappings = try c.decodeIfPresent([Gesture: PalmoAction].self, forKey: .mappings) ?? d.mappings
        appOverrides = try c.decodeIfPresent([String: [Gesture: PalmoAction]].self, forKey: .appOverrides) ?? d.appOverrides
        appNames = try c.decodeIfPresent([String: String].self, forKey: .appNames) ?? d.appNames
        useAppleIntelligence = try c.decodeIfPresent(Bool.self, forKey: .useAppleIntelligence) ?? d.useAppleIntelligence
        showOverlay = try c.decodeIfPresent(Bool.self, forKey: .showOverlay) ?? d.showOverlay
        idleDisarmSeconds = try c.decodeIfPresent(Double.self, forKey: .idleDisarmSeconds) ?? d.idleDisarmSeconds
        typingGuardSeconds = try c.decodeIfPresent(Double.self, forKey: .typingGuardSeconds) ?? d.typingGuardSeconds
        pauseOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? d.pauseOnLowPower
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        pointerPrecision = try c.decodeIfPresent(Double.self, forKey: .pointerPrecision) ?? d.pointerPrecision
        pointerAcceleration = try c.decodeIfPresent(Double.self, forKey: .pointerAcceleration) ?? d.pointerAcceleration
        pointerSmoothing = try c.decodeIfPresent(Double.self, forKey: .pointerSmoothing) ?? d.pointerSmoothing
        pointerAnchor = (try? c.decodeIfPresent(PointerAnchor.self, forKey: .pointerAnchor)) ?? d.pointerAnchor
        snapToTargets = try c.decodeIfPresent(Bool.self, forKey: .snapToTargets) ?? d.snapToTargets
        snapRadius = try c.decodeIfPresent(Double.self, forKey: .snapRadius) ?? d.snapRadius
    }

    /// Factory defaults for rebindable gestures.
    public static let defaultMappings: [Gesture: PalmoAction] = [
        .swipeLeft: .nextSpace,
        .swipeRight: .previousSpace,
        .threeFingerUp: .missionControl,
        .threeFingerDown: .appExpose,
        .thumbFlickRight: .appSwitcherNext,
        .thumbFlickLeft: .appSwitcherPrevious,
        .thumbsUp: .playPause,
        .peaceFlickRight: .nextTrack,
        .peaceFlickLeft: .previousTrack,
        .palmFlip: .contextual,
    ]

    /// Factory settings.
    public static let `default` = PalmoSettings()

    /// Whether a gesture is enabled.
    public func isEnabled(_ gesture: Gesture) -> Bool { enabledGestures.contains(gesture) }

    /// Returns a copy with sensitivity and gain clamped to supported ranges.
    public func sanitized() -> PalmoSettings {
        var copy = self
        copy.sensitivity = min(max(sensitivity, 0.5), 1.5)
        copy.cursorGain = min(max(cursorGain, 0.5), 3)
        copy.idleDisarmSeconds = min(max(idleDisarmSeconds, 5), 300)
        copy.typingGuardSeconds = min(max(typingGuardSeconds, 0), 3)
        copy.pointerPrecision = min(max(pointerPrecision, 0.15), 1)
        copy.pointerAcceleration = min(max(pointerAcceleration, 0), 4)
        copy.pointerSmoothing = min(max(pointerSmoothing, 0), 1)
        copy.snapRadius = min(max(snapRadius, 4), 40)
        copy.enabledGestures.insert(.arm)
        copy.enabledGestures.insert(.disarm)
        return copy
    }
}

/// The part of the hand that steers the pointer.
public enum PointerAnchor: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// The index and middle knuckles. They barely move when you pinch, so clicks land where you aimed.
    case knuckles
    /// The index fingertip. More direct, but the tip shifts as the thumb comes in to pinch.
    case fingertip

    /// Stable identifier for SwiftUI.
    public var id: String { rawValue }

    /// Human-readable name.
    public var title: String {
        switch self {
        case .knuckles: "Knuckles (steadier clicks)"
        case .fingertip: "Fingertip (more direct)"
        }
    }
}
