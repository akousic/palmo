import AppKit
import CoreGraphics
import Foundation
import Synchronization

/// Seconds since the user last pressed a key, excluding keys Palmo posted itself.
public struct KeyboardActivity: Sendable {
    private let log: SyntheticInputLog

    /// Creates a reader that ignores Palmo's synthetic keys recorded in `log`.
    public init(log: SyntheticInputLog) {
        self.log = log
    }

    /// Seconds since the last physical key press (`.infinity` right after Palmo typed).
    public var secondsSinceUserKey: Double {
        let system = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        // If the most recent key was Palmo's own, treat the keyboard as idle.
        return abs(system - log.secondsSinceSyntheticKey) < 0.05 ? .infinity : system
    }
}

/// Tracks the frontmost application. Thread-safe; updated from the main thread by workspace notifications.
public final class FrontmostAppTracker: Sendable {
    private let state = Mutex<AppContext>(.unknown)
    // Written once in init (before the instance is shared) and read in deinit.
    nonisolated(unsafe) private var observer: NSObjectProtocol?

    /// Creates a tracker and starts observing app activation.
    @MainActor
    public init() {
        update(NSWorkspace.shared.frontmostApplication)
        let token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.update(app)
        }
        observer = token
    }

    deinit {
        if let token = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    /// The current frontmost app.
    public var current: AppContext { state.withLock { $0 } }

    private func update(_ app: NSRunningApplication?) {
        guard let app, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return }
        state.withLock { $0 = AppContext(bundleID: bundleID, name: app.localizedName ?? bundleID) }
    }
}

/// Observes Low Power Mode, display sleep and fast user switching, so capture can pause.
@MainActor
public final class PowerMonitor {
    /// Whether Low Power Mode is on.
    public private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Whether the displays are asleep.
    public private(set) var isScreenAsleep = false
    /// Whether this user session is active (not switched away).
    public private(set) var isSessionActive = true

    /// Called on the main actor whenever any signal changes.
    public var onChange: (@MainActor () -> Void)?

    private var tokens: [NSObjectProtocol] = []

    /// Creates a monitor and starts observing.
    public init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.onChange?()
            }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, @MainActor (PowerMonitor) -> Void)] = [
            (NSWorkspace.screensDidSleepNotification, { $0.isScreenAsleep = true }),
            (NSWorkspace.screensDidWakeNotification, { $0.isScreenAsleep = false }),
            (NSWorkspace.sessionDidResignActiveNotification, { $0.isSessionActive = false }),
            (NSWorkspace.sessionDidBecomeActiveNotification, { $0.isSessionActive = true }),
        ]
        for (name, apply) in pairs {
            tokens.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    apply(self)
                    self.onChange?()
                }
            })
        }
    }

    /// Whether capture should be paused given these signals and the user's Low Power preference.
    public func shouldPause(pauseOnLowPower: Bool) -> Bool {
        isScreenAsleep || !isSessionActive || (pauseOnLowPower && isLowPowerMode)
    }
}
