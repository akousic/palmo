import AppIntents
import PalmoCore

/// Arms Palmo's gestures (Shortcuts, Spotlight, Siri).
struct ArmPalmoIntent: AppIntent {
    static let title: LocalizedStringResource = "Arm Palmo Gestures"
    static let description = IntentDescription("Starts responding to hand gestures.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.setArmed(true)
        return .result(dialog: "Palmo is armed.")
    }
}

/// Disarms Palmo's gestures.
struct DisarmPalmoIntent: AppIntent {
    static let title: LocalizedStringResource = "Disarm Palmo Gestures"
    static let description = IntentDescription("Stops responding to hand gestures until you arm again.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        await AppModel.shared.setArmed(false)
        return .result(dialog: "Palmo is disarmed.")
    }
}

/// Turns camera tracking on or off.
struct SetPalmoTrackingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Palmo Camera Tracking"
    static let description = IntentDescription("Turns Palmo's camera tracking on or off.")

    @Parameter(title: "Enabled")
    var enabled: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.trackingEnabled = enabled
        return .result()
    }
}

/// Configures a gesture mapping from a sentence.
struct ConfigurePalmoGestureIntent: AppIntent {
    static let title: LocalizedStringResource = "Configure Palmo Gesture"
    static let description = IntentDescription("Describe a mapping, like “make thumbs up pause my music”.")

    @Parameter(title: "Request")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await AppModel.shared.configure(from: request)
        return .result(dialog: "\(reply)")
    }
}

/// Spotlight / Siri phrases.
struct PalmoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ArmPalmoIntent(), phrases: ["Arm \(.applicationName)"],
                    shortTitle: "Arm Gestures", systemImageName: "hand.raised.fill")
        AppShortcut(intent: DisarmPalmoIntent(), phrases: ["Disarm \(.applicationName)"],
                    shortTitle: "Disarm Gestures", systemImageName: "hand.raised.slash")
    }
}
