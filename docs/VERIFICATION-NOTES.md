# Verification Notes

The environment, as recorded on 2026-10-28:

- MacBook on macOS 26.5.1 (arm64)
- Xcode 26.6, SDK macosx26.5, Swift 6.3.3
- Apple Intelligence available
- Signing identity: Apple Development (free account)

## Verified by compiling or running

| What | How | Result |
|---|---|---|
| The whole package builds in Swift 6 language mode against SDK 26.5 | `swift build` and `swift build -c release` | ✅ 0 errors, 0 warnings |
| FoundationModels API shapes | Checked by compiling, not from memory: `SystemLanguageModel.default.isAvailable` and `.availability`, `LanguageModelSession(tools:instructions:)`, `Tool` with `@Generable` arguments, `@Generable`/`@Guide(.anyOf)`, `respond(to:generating:)`, `prewarm()` | ✅ compiles |
| Foundation Models at runtime | `FoundationModelsTests` call the real on-device model: the smart gesture in Keynote, and natural-language configuration | ✅ passed (about 4.8 s) |
| Recognition logic | `PoseClassifierTests` and `GestureRecognizerTests`, with synthetic 21-joint hands (all shapes; translation, scale and mirror invariance; hysteresis; arm and disarm; typing guard; face zone; click, double-click and drag; right-click; scroll; dial; swipes and flicks; thumbs-up cooldown; palm flip; Core ML threshold) | ✅ |
| Filtering and cursor mapping | `OneEuroFilterTests`, `CursorMapperTests` | ✅ |
| Mapping and intent | `MappingTests` (overrides, sanitizing, Codable, rule parser, configurator in rules mode) and `IntentRouterTests` (fast path skips the model, scroll sign, drag release, model then cache, timeout to rules, `withTimeout`) | ✅ |
| Test totals | `swift test` | ✅ **59 tests in 7 suites, all passing** |
| App bundle and signing | `scripts/build-app.sh`, then `codesign --verify --strict` and `codesign -dv` | ✅ Identifier `com.kousic.palmo`, hardened runtime (`flags=0x10000(runtime)`), Authority "Apple Development: akousic@gmail.com (QZDLFRLQBU)", TeamIdentifier L8S2ZS7494, with the camera and apple-events entitlements |

## Not verified: needs a hands-on check

- **Pointer feel (0.2.0).** The precision and acceleration defaults and the 0.2 s click settle are tuned from
  unit tests, not live use. Adjust them in Settings → Feel.
- **Snap to targets and Close/Minimize window** use Accessibility hit-testing with a 50 ms timeout. They are
  unit-tested with a mock only. Apps with poor Accessibility support, including some Electron apps, may not
  snap.

The app was **built but never launched** during development, so no permission prompts were triggered
unattended. These steps need a person in front of the Mac:

1. **End-to-end tracking quality** with a real camera and real hands. The thresholds were tuned on synthetic
   geometry: extended finger ratio about 1.3, curled about 0.63, pinch gap relative to palm size. They may need
   adjusting. Use the Sensitivity slider first.
2. **Permission flows.**
   - The Camera prompt appears from *Allow Camera*.
   - Onboarding picks up the Accessibility grant by polling.
   - The Automation prompt appears on the first Music, Spotify or Keynote action.
   - Grants survive a rebuild with the same identity.
3. **Mission Control launch arguments.** Launching `Mission Control.app` with argument `2` (App Exposé) and `1`
   (Show Desktop) is long-standing but undocumented behavior. Plain launch (Mission Control) is reliable.
4. **Spaces shortcuts.** Ctrl+←/→ (posted with the fn flag, as the hardware sends it) only work if
   *Move left/right a space* is turned on in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.
   It is on by default.
5. **Scroll direction.** Content is meant to follow the hand ("natural"), regardless of the system's natural
   scrolling setting. The unit test pins the sign, not how it feels.
6. **Media and volume keys.** These are posted as `NSEvent` system-defined events (subtype 8). Play/pause goes to
   whichever app macOS's Now Playing routes it to.
7. **App switcher.** Holding ⌘ for 900 ms after Tab shows the switcher briefly before committing.
8. **Create ML compatibility.** The joint order and coordinate convention of the `[frames, 3, 21]` input are
   implemented from Create ML's documented hand-pose format. No model trained in Create ML has been loaded yet.
9. **App Intents in Shortcuts.** The intents compile and are linked in. SwiftPM does not run Xcode's App Intents
   metadata processor, so no `Metadata.appintents` is generated, and the intents **probably won't appear in
   Shortcuts or Spotlight**. The tool exists at `xcrun appintentsmetadataprocessor`, but hooking it into a SwiftPM
   build is listed in ROADMAP.md.
10. **The overlay panel** stays click-through and above full-screen apps.
11. **Low Power Mode, screen sleep and screen lock** actually pause the camera (the green light goes off).

## Quick manual test script

1. `scripts/build-app.sh && open build/Palmo.app`. Grant Camera and Accessibility.
2. Open palm for 1 s: the menu bar icon shows armed, and the overlay shows the skeleton.
3. Point and move: the pointer follows. A quick pinch clicks. Pinch-hold-move drags a Finder window.
4. Middle pinch shows a context menu. Two fingers moving scrolls Safari. The dial changes the volume HUD.
5. Swipe changes Spaces. Three-finger flick opens Mission Control. Thumbs up plays or pauses Music.
6. Palm flip in Safari reloads the page. In Settings → Ask, type "in Safari, palm flip goes back" and check it.
7. Hold a fist for 1 s: Palmo disarms.

## 0.3.0 arming

- Covered by unit tests (ArmingTests): dropouts, misreads, gap reset, relaxed palm, non-palms, typing, progress, minimum frames and settings decoding.
- Needs a manual check on hardware: arming from different distances and lighting, palm beside the face, the ⌃⌥⌘P shortcut and the overlay ring.
