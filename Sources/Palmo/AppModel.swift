import AppKit
import Observation
import PalmoCore

/// The app's single source of truth on the main actor: settings, permissions, engine lifecycle and status.
@MainActor
@Observable
final class AppModel {
    /// Shared instance (also used by App Intents).
    static let shared = AppModel()

    /// User settings; every change is persisted and pushed to the engine.
    var settings: PalmoSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            let snapshot = settings
            Task { await engine.update(settings: snapshot) }
            overlay.setVisible(snapshot.showOverlay && isRunning)
            if snapshot.pauseOnLowPower != oldValue.pauseOnLowPower { reevaluatePower() }
        }
    }

    /// Latest engine snapshot.
    private(set) var status = EngineStatus()
    /// Camera permission.
    private(set) var cameraPermission = Permissions.camera
    /// Accessibility permission.
    private(set) var accessibilityPermission = Permissions.accessibility
    /// Whether the camera pipeline is running.
    private(set) var isRunning = false
    /// Why tracking is paused, if it is paused automatically.
    private(set) var pauseReason: String?
    /// Last error shown in the menu.
    var lastError: String?
    /// Whether a Core ML motion model is loaded.
    private(set) var motionModelLoaded = false
    /// Whether the user wants tracking on (persisted).
    var trackingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(trackingEnabled, forKey: "trackingEnabled")
            Task { await applyTrackingState() }
        }
    }

    /// Apple Intelligence availability text.
    var appleIntelligenceStatus: String { FoundationModelsContextResolver.availabilityDescription }
    /// Whether the on-device model can be used right now.
    var appleIntelligenceAvailable: Bool { FoundationModelsContextResolver.isModelAvailable }

    let capture = CameraCapture()
    private let log = SyntheticInputLog()
    private let frontmost = FrontmostAppTracker()
    private let power = PowerMonitor()
    private let modelResolver = FoundationModelsContextResolver()
    private let router: IntentRouter
    private let engine: GestureEngine
    private let overlay = OverlayController()
    private var engineTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?

    private init() {
        let loaded = SettingsStore.load()
        settings = loaded
        trackingEnabled = UserDefaults.standard.object(forKey: "trackingEnabled") as? Bool ?? true
        let synthesizer = SystemInputSynthesizer(log: log)
        router = IntentRouter(settings: loaded, synthesizer: synthesizer, modelResolver: modelResolver)
        let capture = self.capture
        engine = GestureEngine(settings: loaded, router: router, frontmost: frontmost,
                               keyboard: KeyboardActivity(log: log),
                               setFrameRate: { fps in capture.setTargetFrameRate(fps) })
        power.onChange = { [weak self] in self?.reevaluatePower() }
        statusTask = Task { [weak self, engine] in
            for await snapshot in engine.status {
                guard let self else { return }
                self.status = snapshot
                self.overlay.update(snapshot)
            }
        }
        engineTask = Task { [engine, capture] in await engine.run(frames: capture.frames) }
        overlay.model = self
    }

    /// Called once at launch.
    func launch() async {
        refreshPermissions()
        await reloadMotionModel()
        if settings.useAppleIntelligence { Task { await modelResolver.prewarm() } }
        if !settings.hasCompletedOnboarding || cameraPermission != .granted || accessibilityPermission != .granted {
            OnboardingWindowController.shared.show(model: self)
        }
        await applyTrackingState()
    }

    /// Re-reads permission state (cheap; call when windows appear).
    func refreshPermissions() {
        cameraPermission = Permissions.camera
        accessibilityPermission = Permissions.accessibility
    }

    /// Requests camera access, then starts tracking if allowed.
    func requestCamera() async {
        _ = await Permissions.requestCamera()
        refreshPermissions()
        await applyTrackingState()
    }

    /// Shows the Accessibility prompt.
    func requestAccessibility() {
        Permissions.promptAccessibility()
        refreshPermissions()
    }

    /// Arms or disarms gestures.
    func setArmed(_ armed: Bool) async {
        await engine.setArmed(armed)
    }

    /// Finishes onboarding and starts tracking.
    func completeOnboarding() async {
        settings.hasCompletedOnboarding = true
        OnboardingWindowController.shared.close()
        await applyTrackingState()
    }

    /// Starts or stops capture to match the user's choice, permissions and power state.
    func applyTrackingState() async {
        refreshPermissions()
        let paused = power.shouldPause(pauseOnLowPower: settings.pauseOnLowPower)
        pauseReason = paused ? (power.isLowPowerMode ? "Paused in Low Power Mode" : "Paused while the screen is off") : nil
        let shouldRun = trackingEnabled && settings.hasCompletedOnboarding && cameraPermission == .granted && !paused
        if shouldRun && !isRunning {
            do {
                try await capture.start()
                isRunning = true
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        } else if !shouldRun && isRunning {
            await engine.setArmed(false)
            capture.stop()
            isRunning = false
        }
        overlay.setVisible(settings.showOverlay && isRunning)
    }

    private func reevaluatePower() {
        Task { await applyTrackingState() }
    }

    /// Loads the optional Core ML motion model if installed.
    func reloadMotionModel() async {
        do {
            let classifier = try await MotionClassifier.loadInstalled()
            await engine.setMotionClassifier(classifier)
            motionModelLoaded = classifier != nil
        } catch {
            motionModelLoaded = false
            lastError = "Motion model: \(error.localizedDescription)"
        }
    }

    /// Interprets a natural-language mapping request and applies it. Returns a confirmation or error message.
    func configure(from text: String) async -> String {
        let configurator = MappingConfigurator(useAppleIntelligence: settings.useAppleIntelligence)
        guard let (change, source) = await configurator.interpret(text) else {
            return "Sorry, I couldn't match that to a gesture and an action. Try “make thumbs up play/pause”."
        }
        var bundleID: String?
        if let name = change.appName {
            guard let found = AppLookup.bundleID(forAppNamed: name) else {
                return "I understood \(change.summary), but couldn't find an app named \(name)."
            }
            bundleID = found
            settings.appNames[found] = name
        }
        settings = settings.applying(change, bundleID: bundleID)
        await router.clearCache()
        let via = source == .appleIntelligence ? "Apple Intelligence" : "built-in rules"
        return "Done: \(change.summary) (understood by \(via))."
    }

    /// Records a training clip for `label`, returning the saved file URL.
    func recordTrainingClip(label: String, seconds: Double = 2.5) async -> URL? {
        guard isRunning else { return nil }
        let url = TrainingLibrary.newClipURL(label: label)
        return await withCheckedContinuation { continuation in
            capture.recordClip(to: url, duration: seconds) { continuation.resume(returning: $0) }
        }
    }

    /// The frontmost app (excluding Palmo).
    var frontmostApp: AppContext { frontmost.current }
}

/// Persists settings as JSON in user defaults.
enum SettingsStore {
    private static let key = "settings.v1"

    /// Loads saved settings or defaults.
    static func load() -> PalmoSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(PalmoSettings.self, from: data) else { return .default }
        return settings.sanitized()
    }

    /// Saves settings.
    static func save(_ settings: PalmoSettings) {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Finds an installed app's bundle identifier by display name.
enum AppLookup {
    /// Running apps first, then /Applications, /System/Applications and ~/Applications.
    static func bundleID(forAppNamed name: String) -> String? {
        let lower = name.lowercased()
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.lowercased() == lower }),
           let id = running.bundleIdentifier {
            return id
        }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        let fm = FileManager.default
        for folder in folders {
            guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
            if let match = items.first(where: { $0.lowercased() == lower + ".app" }) {
                return Bundle(path: folder + "/" + match)?.bundleIdentifier
            }
        }
        return nil
    }

    /// Visible running apps for the per-app picker.
    static func runningApps() -> [AppContext] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { AppContext(bundleID: $0, name: app.localizedName ?? $0) } }
            .sorted { $0.name < $1.name }
    }
}
