import AppKit
import PalmoCore
import SwiftUI

/// Owns the onboarding window (a plain NSWindow, since the menu bar app has no main window).
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    /// Shows (or focuses) onboarding.
    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Welcome to Palmo"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Closes onboarding.
    func close() {
        window?.close()
    }
}

/// First-run guide: explains privacy, requests permissions and teaches arm/disarm.
struct OnboardingView: View {
    let model: AppModel
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill").font(.system(size: 40)).foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Control your Mac with your hands").font(.title2.bold())
                    Text("Everything runs on this Mac. No video, images or hand data ever leave it.")
                        .foregroundStyle(.secondary)
                }
            }

            step(number: 1, title: "Camera", done: model.cameraPermission == .granted,
                 detail: "Palmo watches for your hand with the built-in camera. The green light is on only while tracking.") {
                switch model.cameraPermission {
                case .granted: EmptyView()
                case .notDetermined: Button("Allow Camera") { Task { await model.requestCamera() } }
                case .denied:
                    VStack(alignment: .leading) {
                        Text("Camera access was denied. Turn on Palmo in System Settings, then return here.")
                            .font(.caption).foregroundStyle(.orange)
                        Button("Open Camera Settings") { Permissions.openCameraSettings() }
                    }
                }
            }

            step(number: 2, title: "Accessibility", done: model.accessibilityPermission == .granted,
                 detail: "Lets Palmo move the pointer, click, scroll and press shortcuts for you.") {
                if model.accessibilityPermission != .granted {
                    VStack(alignment: .leading) {
                        Text("Turn on Palmo under Privacy & Security › Accessibility. If it's already on, toggle it off and on.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Open Accessibility Settings") {
                            model.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }

            step(number: 3, title: "Arm and disarm", done: false,
                 detail: "✋ Hold an open palm toward the camera for about a second to arm. ✊ Hold a fist to disarm. Palmo disarms itself when you stop gesturing or start typing.") {
                EmptyView()
            }

            Spacer()
            HStack {
                Text(model.appleIntelligenceAvailable ? "✨ Apple Intelligence available for smart gestures."
                                                      : "Smart gestures will use built-in rules.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(model.cameraPermission == .granted ? "Start Palmo" : "Later") {
                    Task { await model.completeOnboarding() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .onReceive(poll) { _ in model.refreshPermissions() }
    }

    private func step<Content: View>(number: Int, title: String, done: Bool, detail: String,
                                     @ViewBuilder action: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2).foregroundStyle(done ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).fixedSize(horizontal: false, vertical: true)
                action()
            }
        }
    }
}
