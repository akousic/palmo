import PalmoCore
import SwiftUI

/// The Settings window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model).tabItem { Label("General", systemImage: "gearshape") }
            GestureSettings(model: model).tabItem { Label("Gestures", systemImage: "hand.wave") }
            AppOverrideSettings(model: model).tabItem { Label("Apps", systemImage: "square.grid.2x2") }
            NaturalLanguageSettings(model: model).tabItem { Label("Ask", systemImage: "sparkles") }
            TrainingSettings(model: model).tabItem { Label("Training", systemImage: "record.circle") }
        }
        .frame(width: 560, height: 480)
        .onAppear { model.refreshPermissions() }
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Tracking") {
                Toggle("Camera tracking", isOn: $model.trackingEnabled)
                Toggle("Show overlay", isOn: $model.settings.showOverlay)
                Toggle("Pause in Low Power Mode", isOn: $model.settings.pauseOnLowPower)
            }
            Section("Feel") {
                LabeledContent("Sensitivity") {
                    Slider(value: $model.settings.sensitivity, in: 0.5...1.5) { Text("Sensitivity") }
                }
                LabeledContent("Pointer speed") {
                    Slider(value: $model.settings.cursorGain, in: 0.5...3.0) { Text("Pointer speed") }
                }
                LabeledContent("Fine control when moving slowly") {
                    Slider(value: $model.settings.pointerPrecision, in: 0.15...1.0) { Text("Precision") }
                        minimumValueLabel: { Text("Finer").font(.caption) } maximumValueLabel: { Text("Off").font(.caption) }
                }
                LabeledContent("Acceleration for fast moves") {
                    Slider(value: $model.settings.pointerAcceleration, in: 0...4) { Text("Acceleration") }
                }
                LabeledContent("Jitter smoothing") {
                    Slider(value: $model.settings.pointerSmoothing, in: 0...1) { Text("Smoothing") }
                }
                Picker("Pointer follows", selection: $model.settings.pointerAnchor) {
                    ForEach(PointerAnchor.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Snap clicks onto nearby buttons", isOn: $model.settings.snapToTargets)
                LabeledContent("Auto-disarm after idle") {
                    Stepper("\(Int(model.settings.idleDisarmSeconds)) s", value: $model.settings.idleDisarmSeconds, in: 5...120, step: 5)
                }
                LabeledContent("Ignore gestures after typing") {
                    Stepper(String(format: "%.1f s", model.settings.typingGuardSeconds),
                            value: $model.settings.typingGuardSeconds, in: 0...3, step: 0.2)
                }
            }
            Section("Apple Intelligence") {
                Toggle("Use Apple Intelligence for smart gestures and Ask", isOn: $model.settings.useAppleIntelligence)
                Text(model.appleIntelligenceStatus).font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Camera", value: model.cameraPermission == .granted ? "Allowed" : "Not allowed")
                LabeledContent("Accessibility", value: model.accessibilityPermission == .granted ? "Allowed" : "Not allowed")
                HStack {
                    Button("Camera Settings") { Permissions.openCameraSettings() }
                    Button("Accessibility Settings") { Permissions.openAccessibilitySettings() }
                    Button("Automation Settings") { Permissions.openAutomationSettings() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GestureSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Always on") {
                Text("✋ Hold an open palm to arm · ✊ hold a fist to disarm").foregroundStyle(.secondary)
            }
            Section("Gestures") {
                ForEach(PalmoCore.Gesture.allCases.filter { $0 != .arm && $0 != .disarm }) { gesture in
                    HStack {
                        Toggle(isOn: enabled(gesture)) { Text("\(gesture.emoji) \(gesture.title)") }
                        Spacer()
                        if gesture.isRebindable {
                            Picker("", selection: mapping(gesture)) {
                                ForEach(PalmoAction.mappable) { Text($0.title).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 200)
                        } else {
                            Text("Built in").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Button("Restore Default Mappings") { model.settings.mappings = PalmoSettings.defaultMappings }
        }
        .formStyle(.grouped)
    }

    private func enabled(_ gesture: PalmoCore.Gesture) -> Binding<Bool> {
        Binding(get: { model.settings.isEnabled(gesture) },
                set: { on in
                    if on { model.settings.enabledGestures.insert(gesture) } else { model.settings.enabledGestures.remove(gesture) }
                })
    }

    private func mapping(_ gesture: PalmoCore.Gesture) -> Binding<PalmoAction> {
        Binding(get: { model.settings.mappings[gesture] ?? .none },
                set: { model.settings.mappings[gesture] = $0 })
    }
}

struct AppOverrideSettings: View {
    @Bindable var model: AppModel
    @State private var selected: String?
    @State private var running: [AppContext] = []

    var body: some View {
        HSplitView {
            VStack(alignment: .leading) {
                List(selection: $selected) {
                    ForEach(model.settings.appOverrides.keys.sorted(), id: \.self) { id in
                        Text(model.settings.appNames[id] ?? id).tag(id)
                    }
                }
                HStack {
                    Menu("Add App") {
                        ForEach(running, id: \.bundleID) { app in
                            Button(app.name) {
                                model.settings.appNames[app.bundleID] = app.name
                                if model.settings.appOverrides[app.bundleID] == nil {
                                    model.settings.appOverrides[app.bundleID] = [:]
                                }
                                selected = app.bundleID
                            }
                        }
                    }
                    Button("Remove") {
                        if let selected { model.settings.appOverrides[selected] = nil }
                        selected = nil
                    }
                    .disabled(selected == nil)
                }
                .padding(6)
            }
            .frame(minWidth: 180)

            if let id = selected, model.settings.appOverrides[id] != nil {
                Form {
                    Section("Overrides for \(model.settings.appNames[id] ?? id)") {
                        ForEach(PalmoCore.Gesture.rebindable) { gesture in
                            Picker("\(gesture.emoji) \(gesture.title)", selection: override(id, gesture)) {
                                Text("Use global").tag(PalmoAction?.none)
                                ForEach(PalmoAction.mappable) { Text($0.title).tag(PalmoAction?.some($0)) }
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("Select or add an app to give gestures app-specific actions.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { running = AppLookup.runningApps() }
    }

    private func override(_ id: String, _ gesture: PalmoCore.Gesture) -> Binding<PalmoAction?> {
        Binding(get: { model.settings.appOverrides[id]?[gesture] },
                set: { model.settings.appOverrides[id, default: [:]][gesture] = $0 })
    }
}

struct NaturalLanguageSettings: View {
    let model: AppModel
    @State private var text = ""
    @State private var reply = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Describe a mapping in plain English.").font(.headline)
            Text("Examples: “make thumbs up pause my music”, “in Keynote, swipe left goes to the next slide”, “palm flip should be smart”.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("What should a gesture do?", text: $text)
                    .onSubmit(apply)
                Button("Apply", action: apply).disabled(text.isEmpty || busy)
            }
            if busy { ProgressView().controlSize(.small) }
            Text(reply).textSelection(.enabled)
            Spacer()
            Text(model.appleIntelligenceAvailable && model.settings.useAppleIntelligence
                 ? "Understood on-device by Apple Intelligence, with built-in rules as a fallback."
                 : "Apple Intelligence is off or unavailable; using built-in rules.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
    }

    private func apply() {
        let request = text
        busy = true
        Task {
            reply = await model.configure(from: request)
            busy = false
        }
    }
}

struct TrainingSettings: View {
    let model: AppModel
    @State private var label = TrainingLibrary.labels[0]
    @State private var counts: [String: Int] = [:]
    @State private var recording = false
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collect clips to train a custom motion model with Create ML (see TRAINING.md).")
                .fixedSize(horizontal: false, vertical: true)
            Picker("Gesture", selection: $label) {
                ForEach(TrainingLibrary.labels, id: \.self) { Text("\($0) (\(counts[$0, default: 0]))").tag($0) }
            }
            HStack {
                Button(recording ? "Recording…" : "Record 2.5 s Clip") { record() }
                    .disabled(recording || !model.isRunning)
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: TrainingLibrary.root, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([TrainingLibrary.root])
                }
            }
            if !model.isRunning { Text("Turn on camera tracking to record.").foregroundStyle(.secondary) }
            Text(message).font(.caption)
            Divider()
            HStack {
                Text(model.motionModelLoaded ? "Custom motion model loaded." : "No custom motion model installed.")
                Spacer()
                Button("Reload Model") { Task { await model.reloadMotionModel() } }
            }
            Text("Install: put PalmoMotion.mlmodel in ~/Library/Application Support/Palmo/Models/")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(20)
        .onAppear { counts = TrainingLibrary.clipCounts() }
    }

    private func record() {
        recording = true
        message = "Perform “\(label)” now…"
        Task {
            let url = await model.recordTrainingClip(label: label)
            recording = false
            message = url.map { "Saved \($0.lastPathComponent)" } ?? "Recording failed."
            counts = TrainingLibrary.clipCounts()
        }
    }
}
