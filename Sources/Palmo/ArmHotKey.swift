import Carbon.HIToolbox
import Foundation

/// Global shortcuts: ⌃⌥⌘P toggles Armed, ⌃⌥⌘W toggles air writing.
/// Uses Carbon `RegisterEventHotKey`, which needs no extra permission.
@MainActor
final class ArmHotKey {
    static let shared = ArmHotKey()
    /// Arm toggle shortcut.
    static let display = "⌃⌥⌘P"
    /// Air-writing toggle shortcut.
    static let airDisplay = "⌃⌥⌘W"

    private var hotKeys: [EventHotKeyRef?] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: @MainActor () -> Void] = [:]

    /// Registers the arm shortcut (id 1).
    func register(_ action: @escaping @MainActor () -> Void) {
        add(id: 1, key: kVK_ANSI_P, action)
    }

    /// Registers the air-writing shortcut (id 2).
    func registerAirWriting(_ action: @escaping @MainActor () -> Void) {
        add(id: 2, key: kVK_ANSI_W, action)
    }

    private func add(id: UInt32, key: Int, _ action: @escaping @MainActor () -> Void) {
        guard actions[id] == nil else { return }
        actions[id] = action
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let id = hotKeyID.id
                Task { @MainActor in ArmHotKey.shared.actions[id]?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(key), UInt32(cmdKey | optionKey | controlKey),
                            EventHotKeyID(signature: OSType(0x504C_4D4F), id: id), // "PLMO"
                            GetApplicationEventTarget(), 0, &ref)
        hotKeys.append(ref)
    }
}
