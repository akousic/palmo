# Mac App Store blockers

Palmo is built for local and direct distribution. These are the things that block a Mac App Store submission
today, and what it would take to fix each one.

| # | Blocker | Why | Path forward |
|---|---|---|---|
| 1 | **Paid Apple Developer Program membership** | A free account can't create App Store distribution certificates or App Store Connect records, and can't notarize. | Enroll ($99/yr). |
| 2 | **App Sandbox is off** | The App Store requires `com.apple.security.app-sandbox`. | Turn on the sandbox and add `com.apple.security.device.camera`. The rows below are what break. |
| 3 | **Synthetic input through `CGEvent` posting** | Sandboxed apps can post events only after the user grants Accessibility, and App Review scrutinizes apps that control other apps. Several sandboxed utilities do this, but approval is not guaranteed. | Keep `AXIsProcessTrustedWithOptions` onboarding, justify it in review notes as an accessibility and input-device app, and provide a demo video. |
| 4 | **Apple Events to Music, Spotify and Keynote** | The sandbox needs `com.apple.security.temporary-exception.apple-events` (a scrutinized exception) or `com.apple.security.scripting-targets` with access groups. Spotify does not publish access groups. | Use scripting targets for Music and Keynote. Use media keys for Spotify (Palmo already uses them when no app script applies). Or drop app-specific scripting. |
| 5 | **Launching `Mission Control.app` with arguments** | Undocumented behavior, and the sandbox may block launching system apps with arguments. | Use the user's keyboard shortcuts (Ctrl+↑/↓) through `CGEvent`, or drop App Exposé and Show Desktop. |
| 6 | **No Xcode project or App Intents metadata** | App Store submissions need an archive with an asset catalog app icon, privacy manifest and a generated `Metadata.appintents`. SwiftPM alone doesn't produce these. | Add a thin Xcode app target that depends on `PalmoCore`. |
| 7 | **Privacy manifest (`PrivacyInfo.xcprivacy`)** | Required. It must declare the required-reason APIs: `UserDefaults` (CA92.1) and system boot time or event timestamps, if `CGEventSource.secondsSinceLastEventType` is classified that way. | Add the manifest in the Xcode target. |
| 8 | **App icon and screenshots** | Palmo currently uses an SF Symbol in the menu bar and has no `AppIcon`. | Design the icon and screenshots. |
| 9 | **User-installed Core ML models** | Allowed, but loading from Application Support must stay inside the sandbox container. The sandboxed path changes to `~/Library/Containers/com.kousic.palmo/…`. | Already uses `URL.applicationSupportDirectory`, so it adapts automatically. Update the docs. |

**Direct distribution** (Developer ID plus notarization) avoids rows 2–8. It still needs the paid membership
(row 1). That is the recommended next step for sharing Palmo with others.
