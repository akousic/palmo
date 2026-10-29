import AppKit
import CoreGraphics
import Foundation
import Synchronization

/// Errors raised while executing actions.
public enum ActionExecutionError: LocalizedError, Sendable {
    /// Accessibility permission is missing, so synthetic input would be dropped.
    case accessibilityNotGranted
    /// A system app could not be launched.
    case launchFailed(String)

    /// Human-readable description.
    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted: "Palmo needs Accessibility permission to control the Mac."
        case .launchFailed(let detail): "Could not open \(detail)."
        }
    }
}

/// Records when Palmo itself last posted a keyboard event, so the typing guard can ignore Palmo's own keys.
public final class SyntheticInputLog: Sendable {
    private let lastKey = Mutex<Date>(.distantPast)

    /// Creates a log.
    public init() {}

    /// Marks that a synthetic key was just posted.
    public func markKey() { lastKey.withLock { $0 = Date() } }

    /// Seconds since Palmo last posted a key.
    public var secondsSinceSyntheticKey: Double { lastKey.withLock { Date().timeIntervalSince($0) } }
}

/// Virtual key codes (US ANSI layout positions) used by Palmo.
enum KeyCode: CGKeyCode {
    case r = 0x0F, t = 0x11, w = 0x0D, z = 0x06, m = 0x2E, f = 0x03, p = 0x23
    case leftBracket = 0x21, rightBracket = 0x1E
    case space = 0x31, escape = 0x35, tab = 0x30, command = 0x37, shift = 0x38
    case leftArrow = 0x7B, rightArrow = 0x7C
}

/// `NX_KEYTYPE_*` constants from IOKit's `ev_keymap.h` for media keys.
enum MediaKey: Int {
    case soundUp = 0, soundDown = 1, mute = 7, play = 16, next = 17, previous = 18
}

/// Posts real input through Core Graphics (`CGEvent`) and opens system apps through `NSWorkspace`.
///
/// Requires Accessibility permission; the app must not be sandboxed.
public actor SystemInputSynthesizer: InputSynthesizing {
    private let source = CGEventSource(stateID: .hidSystemState)
    private let log: SyntheticInputLog
    private var leftDown = false
    private var switcherReleaseTask: Task<Void, Never>?
    private var switcherHeld = false

    /// Creates a synthesizer that reports its key presses to `log`.
    public init(log: SyntheticInputLog) {
        self.log = log
    }

    /// Whether the process is trusted for Accessibility.
    public nonisolated static var isTrusted: Bool { AXIsProcessTrusted() }

    public func cursorPosition() async -> ScreenPoint {
        let location = CGEvent(source: nil)?.location ?? .zero
        return ScreenPoint(x: location.x, y: location.y)
    }

    public func screenBounds() async -> ScreenRect {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(max(count, 1)))
        CGGetActiveDisplayList(count, &ids, &count)
        let union = ids.prefix(Int(count)).map(CGDisplayBounds).reduce(CGRect.null) { $0.union($1) }
        let rect = union.isNull ? CGDisplayBounds(CGMainDisplayID()) : union
        return ScreenRect(minX: rect.minX, minY: rect.minY, maxX: rect.maxX, maxY: rect.maxY)
    }

    public func moveCursor(to point: ScreenPoint, dragging: Bool) async {
        let type: CGEventType = (dragging && leftDown) ? .leftMouseDragged : .mouseMoved
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: CGPoint(x: point.x, y: point.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    public func click(count: Int) async {
        let location = CGPoint(x: (await cursorPosition()).x, y: (await cursorPosition()).y)
        for clickState in 1...max(1, min(count, 3)) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    public func rightClick() async {
        let p = await cursorPosition()
        let location = CGPoint(x: p.x, y: p.y)
        for type in [CGEventType.rightMouseDown, .rightMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .right)?
                .post(tap: .cghidEventTap)
        }
    }

    public func mouseDown() async {
        let p = await cursorPosition()
        leftDown = true
        CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: CGPoint(x: p.x, y: p.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    public func mouseUp() async {
        guard leftDown else { return }
        let p = await cursorPosition()
        leftDown = false
        CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: CGPoint(x: p.x, y: p.y),
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    public func scroll(dx: Int, dy: Int) async {
        guard dx != 0 || dy != 0 else { return }
        CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                wheel1: Int32(clamping: dy), wheel2: Int32(clamping: dx), wheel3: 0)?.post(tap: .cghidEventTap)
    }

    public func volume(steps: Int) async {
        let key: MediaKey = steps > 0 ? .soundUp : .soundDown
        for _ in 0..<abs(steps) { postMediaKey(key) }
    }

    public func clickableFrame(near point: ScreenPoint, radius: Double) async -> ScreenRect? {
        AccessibilityTargets.clickableFrame(near: point, radius: radius)
    }

    public func perform(_ action: PalmoAction, app: AppContext) async throws {
        if let source = AppleScriptRunner.script(for: action, bundleID: app.bundleID) {
            do {
                try await AppleScriptRunner.run(source)
                return
            } catch {
                // Automation denied or the app is not scriptable right now: fall back to synthetic input.
            }
        }
        guard Self.isTrusted else { throw ActionExecutionError.accessibilityNotGranted }
        switch action {
        case .contextual, .none: return
        case .playPause: postMediaKey(.play)
        case .nextTrack: postMediaKey(.next)
        case .previousTrack: postMediaKey(.previous)
        case .volumeUp: postMediaKey(.soundUp)
        case .volumeDown: postMediaKey(.soundDown)
        case .toggleMute: postMediaKey(.mute)
        case .nextSpace: postKey(.rightArrow, flags: [.maskControl, .maskSecondaryFn])
        case .previousSpace: postKey(.leftArrow, flags: [.maskControl, .maskSecondaryFn])
        case .missionControl: try await openMissionControl(arguments: [])
        case .appExpose: try await openMissionControl(arguments: ["2"])
        case .showDesktop: try await openMissionControl(arguments: ["1"])
        case .appSwitcherNext: stepAppSwitcher(backwards: false)
        case .appSwitcherPrevious: stepAppSwitcher(backwards: true)
        case .browserReload, .runBuild: postKey(.r, flags: .maskCommand)
        case .browserBack: postKey(.leftBracket, flags: .maskCommand)
        case .browserForward: postKey(.rightBracket, flags: .maskCommand)
        case .newTab: postKey(.t, flags: .maskCommand)
        case .closeTab: postKey(.w, flags: .maskCommand)
        case .closeWindow:
            // Press the window's own close button (works in tabbed apps too); fall back to ⌘W.
            if !AccessibilityTargets.pressFocusedWindowButton(kAXCloseButtonAttribute) { postKey(.w, flags: .maskCommand) }
        case .minimizeWindow:
            if !AccessibilityTargets.pressFocusedWindowButton(kAXMinimizeButtonAttribute) { postKey(.m, flags: .maskCommand) }
        case .nextSlide: postKey(.rightArrow, flags: .maskSecondaryFn)
        case .previousSlide: postKey(.leftArrow, flags: .maskSecondaryFn)
        case .startSlideshow: postKey(.p, flags: [.maskCommand, .maskAlternate])
        case .quickLook: postKey(.space, flags: [])
        case .toggleMeetingMute: postKey(.m, flags: [.maskCommand, .maskShift])
        case .toggleFullScreen: postKey(.f, flags: [.maskCommand, .maskControl])
        case .undo: postKey(.z, flags: .maskCommand)
        case .escape: postKey(.escape, flags: [])
        }
    }

    /// Types text with Unicode keyboard events, a few characters per event (works for any language and emoji).
    public func typeText(_ text: String) async {
        log.markKey()
        var batch: [Character] = []
        func post(_ chars: [Character]) {
            let units = Array(String(chars).utf16)
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down)
                units.withUnsafeBufferPointer { event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: $0.baseAddress) }
                event?.post(tap: .cghidEventTap)
            }
        }
        for ch in text {
            batch.append(ch)
            if batch.count == 8 {
                post(batch)
                batch.removeAll()
                try? await Task.sleep(for: .milliseconds(6))
            }
        }
        if !batch.isEmpty { post(batch) }
    }

    // MARK: - Helpers

    private func postKey(_ key: KeyCode, flags: CGEventFlags) {
        log.markKey()
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: down)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    private func postMediaKey(_ key: MediaKey) {
        log.markKey()
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            let data1 = (key.rawValue << 16) | (state << 8)
            let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                           modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                                           timestamp: 0, windowNumber: 0, context: nil,
                                           subtype: 8, data1: data1, data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    /// Holds ⌘ while stepping the app switcher; releases it 0.9 s after the last step, which commits the choice.
    private func stepAppSwitcher(backwards: Bool) {
        log.markKey()
        if !switcherHeld {
            let down = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.command.rawValue, keyDown: true)
            down?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            switcherHeld = true
        }
        var flags: CGEventFlags = .maskCommand
        if backwards { flags.insert(.maskShift) }
        for down in [true, false] {
            let tab = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.tab.rawValue, keyDown: down)
            tab?.flags = flags
            tab?.post(tap: .cghidEventTap)
        }
        switcherReleaseTask?.cancel()
        switcherReleaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.releaseAppSwitcher()
        }
    }

    private func releaseAppSwitcher() {
        guard switcherHeld else { return }
        let up = CGEvent(keyboardEventSource: source, virtualKey: KeyCode.command.rawValue, keyDown: false)
        up?.flags = []
        up?.post(tap: .cghidEventTap)
        switcherHeld = false
    }

    private func openMissionControl(arguments: [String]) async throws {
        let url = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw ActionExecutionError.launchFailed("Mission Control")
        }
    }
}
