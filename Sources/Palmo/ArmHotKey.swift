import Carbon.HIToolbox
import Foundation

/// A global ⌃⌥⌘P shortcut that toggles Armed, as a fallback when the open-palm hold won't take.
/// Uses Carbon `RegisterEventHotKey`, which needs no extra permission.
@MainActor
final class ArmHotKey {
    static let shared = ArmHotKey()
    /// Human-readable shortcut.
    static let display = "⌃⌥⌘P"

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    /// Registers the shortcut; `action` runs on each press.
    func register(_ action: @escaping @MainActor () -> Void) {
        guard hotKey == nil else { return }
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            Task { @MainActor in ArmHotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x504C_4D4F), id: 1) // "PLMO"
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey | controlKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }
}
