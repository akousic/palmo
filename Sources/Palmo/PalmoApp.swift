import AppKit
import PalmoCore
import SwiftUI

/// Palmo: hand-gesture control for the Mac, entirely on-device.
@main
struct PalmoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(systemName: model.status.isArmed ? "hand.raised.fill" : (model.isRunning ? "hand.raised" : "hand.raised.slash"))
                .accessibilityLabel(model.status.isArmed ? "Palmo armed" : "Palmo")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

/// Starts the model after launch (MenuBarExtra content is lazy, so launch work lives here).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await AppModel.shared.launch() }
    }
}
