import AppKit
import Foundation

/// Runs small, fixed AppleScripts for app-level actions that are more reliable than synthetic keys.
///
/// Scripts are compiled from constant templates (never from model output), run on the main actor as
/// `NSAppleScript` requires, and need the user's Automation consent per target app.
public enum AppleScriptRunner {
    /// Errors from script execution.
    public struct ScriptError: LocalizedError, Sendable {
        /// The AppleScript error message.
        public let message: String
        /// Human-readable description.
        public var errorDescription: String? { message }
    }

    /// Returns the script source for an action in an app, if Palmo has a scripted implementation.
    public static func script(for action: PalmoAction, bundleID: String) -> String? {
        switch (bundleID, action) {
        case ("com.apple.Music", .playPause), ("com.spotify.client", .playPause):
            "tell application id \"\(bundleID)\" to playpause"
        case ("com.apple.Music", .nextTrack), ("com.spotify.client", .nextTrack):
            "tell application id \"\(bundleID)\" to next track"
        case ("com.apple.Music", .previousTrack), ("com.spotify.client", .previousTrack):
            "tell application id \"\(bundleID)\" to previous track"
        case ("com.apple.iWork.Keynote", .startSlideshow):
            "tell application id \"com.apple.iWork.Keynote\" to start front document"
        case ("com.apple.iWork.Keynote", .nextSlide):
            "tell application id \"com.apple.iWork.Keynote\" to show next"
        case ("com.apple.iWork.Keynote", .previousSlide):
            "tell application id \"com.apple.iWork.Keynote\" to show previous"
        default:
            nil
        }
    }

    /// Executes `source`. Throws `ScriptError` on failure (including a denied Automation prompt).
    @MainActor
    public static func run(_ source: String) throws {
        guard let script = NSAppleScript(source: source) else { throw ScriptError(message: "Invalid script") }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw ScriptError(message: errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript failed")
        }
    }
}
