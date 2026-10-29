import Foundation

/// Decides what the smart gesture means in the frontmost app.
public protocol ContextResolver: Sendable {
    /// Returns the action to run for `gesture` in `app`, or `nil` if nothing sensible applies.
    func resolve(gesture: Gesture, app: AppContext) async throws -> PalmoAction?
}

/// Deterministic fallback used when Apple Intelligence is unavailable, disabled, slow or failing.
public struct RuleBasedContextResolver: ContextResolver {
    /// Bundle identifier → action table.
    public static let table: [String: PalmoAction] = [
        "com.apple.Safari": .browserReload,
        "com.google.Chrome": .browserReload,
        "org.mozilla.firefox": .browserReload,
        "company.thebrowser.Browser": .browserReload,
        "com.microsoft.edgemac": .browserReload,
        "com.apple.iWork.Keynote": .nextSlide,
        "com.microsoft.Powerpoint": .nextSlide,
        "com.apple.Preview": .nextSlide,
        "com.apple.Music": .nextTrack,
        "com.spotify.client": .nextTrack,
        "com.apple.podcasts": .playPause,
        "com.apple.TV": .playPause,
        "com.apple.QuickTimePlayerX": .playPause,
        "com.apple.dt.Xcode": .runBuild,
        "us.zoom.xos": .toggleMeetingMute,
        "com.apple.FaceTime": .toggleMeetingMute,
        "com.microsoft.teams2": .toggleMeetingMute,
        "com.apple.finder": .quickLook,
    ]

    /// Action used for apps that are not in the table.
    public var defaultAction: PalmoAction

    /// Creates the resolver.
    public init(defaultAction: PalmoAction = .missionControl) {
        self.defaultAction = defaultAction
    }

    /// Looks the app up in the table.
    public func resolve(gesture: Gesture, app: AppContext) async throws -> PalmoAction? {
        Self.table[app.bundleID] ?? defaultAction
    }
}
