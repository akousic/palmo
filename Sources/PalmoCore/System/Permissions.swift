@preconcurrency import ApplicationServices
import AppKit
import AVFoundation

/// Authorization state for a privacy permission.
public enum PermissionState: String, Sendable {
    /// Not yet asked.
    case notDetermined
    /// Granted.
    case granted
    /// Denied or restricted; the user must change it in System Settings.
    case denied
}

/// Camera and Accessibility permission helpers.
public enum Permissions {
    /// Current camera authorization.
    public static var camera: PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Shows the system camera prompt (only the first time); returns whether access is granted.
    public static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Whether Palmo is trusted for Accessibility (needed to post input events).
    public static var accessibility: PermissionState {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Asks macOS to show the Accessibility prompt that links to System Settings.
    public static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings › Privacy & Security › Camera.
    @MainActor
    public static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    /// Opens System Settings › Privacy & Security › Accessibility.
    @MainActor
    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Opens System Settings › Privacy & Security › Automation.
    @MainActor
    public static func openAutomationSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }

    @MainActor
    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
