import PalmoCore
import SwiftUI

/// The menu bar popover.
struct MenuContentView: View {
    @Bindable var model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: model.status.isArmed ? "hand.raised.fill" : "hand.raised")
                    .font(.title2)
                    .foregroundStyle(model.status.isArmed ? Color.green : Color.secondary)
                VStack(alignment: .leading) {
                    Text("Palmo").font(.headline)
                    Text(statusLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if model.cameraPermission != .granted || model.accessibilityPermission != .granted {
                PermissionBanner(model: model)
            }
            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }

            Toggle("Camera tracking", isOn: $model.trackingEnabled)
            Toggle("Armed (\(ArmHotKey.display))", isOn: Binding(
                get: { model.status.isArmed },
                set: { armed in Task { await model.setArmed(armed) } }))
                .disabled(!model.isRunning)
            if model.settings.airWritingEnabled {
                Toggle("Air writing (\(ArmHotKey.airDisplay))", isOn: Binding(
                    get: { model.status.airWriting.isActive },
                    set: { on in Task { await model.setAirWriting(on) } }))
                    .disabled(!model.isRunning)
                if model.status.airWriting.isActive {
                    if !model.status.airWriting.preview.isEmpty {
                        Text("“\(model.status.airWriting.preview)”").font(.callout)
                        Button("Type it") { Task { await model.insertAirText() } }
                    }
                    Text("Pinch to write · pause to finish a word · 👍 types · ✌️ deletes a word · ✊ cancels")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Toggle("Show overlay", isOn: $model.settings.showOverlay)

            if let outcome = model.status.lastOutcome {
                Text("Last: \(OutcomeText.describe(outcome))").font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Button("Settings…") {
                NSApp.activate()
                openSettings()
            }
            Button("Setup Guide…") { OnboardingWindowController.shared.show(model: model) }
            Button("Quit Palmo") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 280)
        .onAppear { model.refreshPermissions() }
    }

    private var statusLine: String {
        if let reason = model.pauseReason { return reason }
        if !model.isRunning { return "Camera off" }
        if model.status.airWriting.isActive { return "Air writing" + (model.status.airWriting.pendingWords > 0 ? " · reading…" : "") }
        if model.status.isArmed { return "Armed · \(Int(model.status.framesPerSecond)) fps" }
        if model.status.armProgress > 0 { return "Arming… \(Int(model.status.armProgress * 100))%" }
        if model.status.handVisible, let reason = model.status.armRejection { return "Not arming: \(reason.explanation)" }
        return "Hold an open palm to arm, or press \(ArmHotKey.display)"
    }
}

/// Shown when a permission is missing, with a direct route to fix it.
struct PermissionBanner: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.cameraPermission == .denied {
                Label("Camera access is off", systemImage: "video.slash")
                Button("Open Camera Settings") { Permissions.openCameraSettings() }
            } else if model.cameraPermission == .notDetermined {
                Button("Allow Camera…") { Task { await model.requestCamera() } }
            }
            if model.accessibilityPermission != .granted {
                Label("Accessibility is needed to move the pointer and press keys", systemImage: "accessibility")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility Settings") {
                    model.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
            }
        }
        .font(.caption)
        .padding(8)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
    }
}

/// Human-readable descriptions of router outcomes.
enum OutcomeText {
    static func describe(_ outcome: RoutedOutcome) -> String {
        switch outcome {
        case .fastPath(let text): text
        case .action(let action, let gesture, let source):
            "\(gesture.emoji) \(gesture.title) → \(action.title)" + (source == .appleIntelligence ? " ✨" : "")
        case .ignored(let gesture): "\(gesture.emoji) \(gesture.title) (not mapped)"
        case .failed(let gesture, let message): "\(gesture.title) failed: \(message)"
        case .armState(let armed): armed ? "Armed" : "Disarmed"
        }
    }
}
