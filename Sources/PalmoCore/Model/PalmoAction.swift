import Foundation

/// A high-level, executable action that a discrete gesture can trigger.
public enum PalmoAction: String, CaseIterable, Sendable, Codable, Identifiable {
    /// Ask the context resolver (Foundation Models or rules) to decide based on the frontmost app.
    case contextual
    case playPause, nextTrack, previousTrack
    case volumeUp, volumeDown, toggleMute
    case nextSpace, previousSpace, missionControl, appExpose, showDesktop
    case appSwitcherNext, appSwitcherPrevious
    case browserReload, browserBack, browserForward, newTab, closeTab
    case closeWindow, minimizeWindow
    case nextSlide, previousSlide, startSlideshow
    case quickLook, runBuild, toggleMeetingMute, toggleFullScreen
    case undo, escape
    /// Do nothing (effectively disables the gesture's action).
    case none

    /// Stable identifier for SwiftUI.
    public var id: String { rawValue }

    /// Human-readable title.
    public var title: String {
        switch self {
        case .contextual: "Smart (depends on app)"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next track"
        case .previousTrack: "Previous track"
        case .volumeUp: "Volume up"
        case .volumeDown: "Volume down"
        case .toggleMute: "Mute / Unmute"
        case .nextSpace: "Next Space"
        case .previousSpace: "Previous Space"
        case .missionControl: "Mission Control"
        case .appExpose: "App Exposé"
        case .showDesktop: "Show Desktop"
        case .appSwitcherNext: "Switch to next app"
        case .appSwitcherPrevious: "Switch to previous app"
        case .browserReload: "Reload page"
        case .browserBack: "Back"
        case .browserForward: "Forward"
        case .newTab: "New tab"
        case .closeTab: "Close tab"
        case .closeWindow: "Close window"
        case .minimizeWindow: "Minimize window"
        case .nextSlide: "Next slide"
        case .previousSlide: "Previous slide"
        case .startSlideshow: "Start slideshow"
        case .quickLook: "Quick Look"
        case .runBuild: "Run (⌘R)"
        case .toggleMeetingMute: "Toggle meeting mute (⇧⌘M)"
        case .toggleFullScreen: "Toggle full screen"
        case .undo: "Undo"
        case .escape: "Escape"
        case .none: "Do nothing"
        }
    }

    /// A one-sentence description used as the Foundation Models tool description.
    public var toolDescription: String {
        switch self {
        case .contextual: "Resolve the action from context."
        case .playPause: "Toggle media playback in the current media app."
        case .nextTrack: "Skip to the next song or media item."
        case .previousTrack: "Go back to the previous song or media item."
        case .volumeUp: "Raise the system output volume one step."
        case .volumeDown: "Lower the system output volume one step."
        case .toggleMute: "Mute or unmute system audio output."
        case .nextSpace: "Move to the next desktop Space."
        case .previousSpace: "Move to the previous desktop Space."
        case .missionControl: "Show Mission Control with all windows."
        case .appExpose: "Show all windows of the frontmost app."
        case .showDesktop: "Reveal the desktop."
        case .appSwitcherNext: "Switch to the next app with Command-Tab."
        case .appSwitcherPrevious: "Switch to the previous app with Command-Shift-Tab."
        case .browserReload: "Reload the current web page or refresh the current view (Command-R)."
        case .browserBack: "Navigate back (Command-[)."
        case .browserForward: "Navigate forward (Command-])."
        case .newTab: "Open a new tab (Command-T)."
        case .closeTab: "Close the current tab or window (Command-W)."
        case .closeWindow: "Close the frontmost window by pressing its close button."
        case .minimizeWindow: "Minimize the frontmost window to the Dock."
        case .nextSlide: "Advance to the next slide or page (Right Arrow)."
        case .previousSlide: "Go back one slide or page (Left Arrow)."
        case .startSlideshow: "Start presenting the slideshow (Option-Command-P)."
        case .quickLook: "Preview the selected file with Quick Look (Space)."
        case .runBuild: "Build and run the current project (Command-R)."
        case .toggleMeetingMute: "Toggle the microphone in a video call (Shift-Command-M)."
        case .toggleFullScreen: "Enter or exit full screen (Control-Command-F)."
        case .undo: "Undo the last edit (Command-Z)."
        case .escape: "Press Escape to dismiss or cancel."
        case .none: "Do nothing."
        }
    }

    /// Actions a user can assign to a gesture.
    public static var mappable: [PalmoAction] { allCases }

    /// Raw names of mappable actions (constrains guided generation).
    public static var mappableNames: [String] { mappable.map(\.rawValue) }

    /// Concrete actions the context resolver may choose from (everything except `.contextual`).
    /// Window close/minimize are excluded so a smart gesture never closes a window by surprise.
    public static var contextualCandidates: [PalmoAction] {
        allCases.filter { ![.contextual, .closeWindow, .minimizeWindow].contains($0) }
    }

    /// Raw names of contextual candidates.
    public static var contextualCandidateNames: [String] { contextualCandidates.map(\.rawValue) }
}
