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
                hasCompletedOnboarding: Bool = false) {
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
        copy.enabledGestures.insert(.arm)
        copy.enabledGestures.insert(.disarm)
        return copy
    }
}
