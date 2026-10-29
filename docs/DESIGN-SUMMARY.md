# Palmo — Design Summary (Phase 1 design gate)

Palmo is a macOS 26+ menu-bar app (SwiftUI `MenuBarExtra`) that controls the Mac with hand gestures seen by the built-in camera. Everything runs on-device: AVFoundation → Vision hand pose → rule + Core ML recognition → Foundation Models (high-level intents only) → CGEvent / AppleScript / App Intents. No network calls.

## 1. Environment verified on the target Mac (2026-10-28)

| Item | Finding |
|---|---|
| macOS | 26.5.1 (25F80), arm64 (MacBook Pro) |
| SDK / toolchain | macOS SDK 26.5, Xcode 26.6, Swift 6.3.3 |
| FoundationModels | Present in SDK; `SystemLanguageModel.default.availability == .available` (Apple Intelligence enabled) |
| Vision | `VNDetectHumanHandPoseRequest` revision 1, `maximumHandCount` default 2 |
| CreateML / CreateMLComponents / AppIntents | Present in SDK |
| Cameras | "MacBook Pro Camera" (+ Continuity iPhone camera) |
| Camera TCC | `.notDetermined` for the probe process |
| Signing | One "Apple Development" identity (free Personal Team) |

Probe: `scripts/probe-env.swift`.

### Packaging & permissions plan
- **SwiftPM-only executables get no stable TCC identity.** Camera access requires `NSCameraUsageDescription` in an `.app` bundle's Info.plist, and Accessibility trust (needed for CGEvent posting) is keyed to the bundle ID + code signature.
- **Plan:** SwiftPM package (`PalmoCore` library + `Palmo` executable + tests) plus `scripts/build-app.sh` that runs `swift build -c release`, assembles `Palmo.app` (Info.plist, `LSUIElement=YES`, icon, entitlements), and code-signs it with the Apple Development identity (fallback: ad-hoc `-`). `swift test` runs the unit tests without the bundle.
- **Free account implications:** no Developer ID, no notarization → the app runs only on this Mac (or others after right-click → Open). No 7-day expiry for macOS dev-signed apps run locally, unlike iOS. **Ad-hoc signing changes the cdhash on every rebuild, so macOS resets/invalidates Accessibility (and sometimes Camera) grants each build**; signing with the stable Apple Development identity keeps the designated requirement stable and avoids most resets. Onboarding will detect "trusted == false after rebuild" and explain how to remove/re-add Palmo in System Settings → Privacy & Security → Accessibility.
- Not sandboxed (see App Store blockers).

## 2. Gesture vocabulary

Design rules: hand rests at desk/keyboard level with elbow supported (no gorilla arm); poses are held off the keyboard plane and are *static shapes or deliberate motions* that typing and face-touching don't produce; every gesture uses joint *ratios/angles* (scale-invariant) with Vision confidence ≥ 0.5 per joint, so it tolerates webcam lighting.

Global false-positive guards (apply to all):
- **Armed state required** (except Arm itself). Auto-disarm after 20 s without a recognised gesture.
- **Face zone exclusion:** hand centroid overlapping the upper-centre "face band" (or wrist above chin height estimated from frame) is ignored — kills face-touching.
- **Typing guard:** if keyboard/mouse HID activity occurred in the last 600 ms (CGEventSource seconds-since-last-event), discrete gestures are suppressed.
- **Hysteresis + dwell:** pose must persist N frames (≈150–300 ms) to enter, and drop below a lower threshold to exit; per-gesture cooldowns.
- **Hand-count & confidence gating:** minimum mean joint confidence; ignore partial hands at frame edges.

| # | Gesture | Glyph | Pose / motion | Detection | Action | Why ergonomic & distinct |
|---|---|---|---|---|---|---|
| A | **Arm** | ✋⏸ "Open palm hold" | Flat open palm facing camera, fingers spread, held 0.8 s | Rules: all 4 fingers extended (tip-to-wrist ≫ PIP-to-wrist), thumb abducted, palm normal toward camera; dwell 0.8 s | Arm Palmo (chime + overlay ring fill) | Natural "hello/stop" shape; typing hands are palm-down and curled, never a sustained spread palm facing the camera |
| D | **Disarm** | ✊⬇ "Fist drop" | Closed fist, then lowered out of frame (or held 1 s) | Rules: all fingertips near palm; fist dwell 1 s or fist + downward exit | Disarm (no further actions) | Deliberate, unlike resting hands; fist is the opposite of Arm, easy to remember |
| 1 | **Point & move** | ☝️ "Pointer" | Index extended, others curled, hand at rest height | Rules (index only extended). Index tip → screen via calibrated active box (relative/“trackpad” mapping with gain), One Euro filtered | Move cursor (fast path) | Small wrist/finger motion inside a ~15 cm box at desk level; relative mode lets the elbow stay down |
| 2 | **Pinch click** | 🤏 | Thumb tip touches index tip briefly (<300 ms) while pointing | Thumb–index tip distance / hand-size < 0.25 enter, > 0.35 exit (hysteresis); cursor frozen during pinch to prevent jitter | Left click; two quick pinches = double-click | Mimics trackpad tap; pinch never happens in typing pose |
| 3 | **Pinch hold & drag** | 🤏➡️ | Pinch held > 300 ms, then move | Same detector, time threshold → mouseDown, move → drag, release → mouseUp | Click-drag / select | Same pose family, no new learning |
| 4 | **Middle pinch** | 🤌 (thumb+middle) | Thumb tip touches middle tip | Thumb–middle distance rule with index *not* pinched | Right click | Distinct from index pinch, still one-handed and small |
| 5 | **Two-finger scroll** | ✌️↕️ | Index+middle extended together (“V” closed), move hand up/down/left/right | Rules for 2-finger pose; velocity of finger midpoint → scroll deltas (pixel, with inertia) | Scroll (fast path) | Direct analogue of two-finger trackpad scroll |
| 6 | **Swipe left/right (open hand)** | 👋⬅️➡️ | Open palm sideways sweep > 25% frame width in < 400 ms | Motion: Core ML hand-action classifier when model present; fallback rule on wrist velocity + open-hand pose | Switch Space (Ctrl+←/→) | Big, deliberate, can't occur while typing (hands leave keyboard plane) |
| 7 | **Three-finger swipe up / down** | 🤟⬆️⬇️ (index+middle+ring) | Three fingers extended, flick up or down | Pose rule + vertical velocity | Up: Mission Control; Down: App Exposé | Mirrors 3/4-finger trackpad swipes |
| 8 | **Thumb flick (app switcher)** | 👍↔️ | Thumb-out fist, flick sideways | Pose + horizontal wrist velocity; each flick = Tab step while ⌘ held, open hand releases | ⌘-Tab next/previous app | Hitchhiker thumb is unmistakable; holds ⌘ until release |
| 9 | **Thumbs up** | 👍 | Static thumbs-up 0.5 s | Pose rule (thumb up, tip above IP, fingers curled) | Play/Pause media (default) — NL-configurable | Iconic, easily held at desk height |
| 10 | **Volume dial** | 🤏🔄 “knob” | Thumb+index pinch with other fingers up (“OK”-ish), rotate wrist | Pose rule + roll angle of index-MCP→pinky-MCP vector; detents every 12° | Volume up/down (system key events) | Feels like turning a knob; rotation at rest is small |
| 11 | **Next/Prev track** | ✌️👉 / 👈 | Peace sign tilted & flicked right/left | Pose + horizontal flick (cooldown 800 ms) | Next / Previous track | Separate from scroll by spread "V" vs closed pair |
| 12 | **Smart gesture “Do the thing”** | 🖐️🔁 “Palm flip” | Open palm flipped to back-of-hand and back within 700 ms | Motion: palm-normal sign change twice (thumb side crosses) or classifier | **Context-aware** via Foundation Models: resolves by frontmost app, e.g. Safari → reload/back, Keynote → next slide, Music → next track, Xcode → Run (⌘R), Zoom/FaceTime → mute toggle, Finder → Quick Look | Rare natural motion; deliberate rotation, no reach |

Users can rebind any discrete gesture (6–12) via natural language ("make thumbs up pause my music", "in Keynote, palm flip should start the slideshow"), enable/disable each gesture, tune sensitivity, and set per-app overrides.

## 3. Architecture summary

```
Capture → Hand Tracking → Gesture Recognition → Intent → Action Execution
(AVFoundation) (Vision)    (rules + Core ML)    (fast path | FM | rules) (CGEvent/AppleScript/AppIntents)
```

Layers / types (Swift 6 strict concurrency):
- **CaptureService** (`actor`, own serial `DispatchQueue` for `AVCaptureVideoDataOutput` delegate): 640×480, 30 fps active / 10 fps idle, drops late frames (`alwaysDiscardsLateVideoFrames`).
- **HandTracker** (`final class`, used only on the capture queue, `Sendable` output): `VNImageRequestHandler` + `VNDetectHumanHandPoseRequest`, emits `HandObservation` (21 joints, confidences, chirality) — value types, `Sendable`.
- **GestureRecognizer** (`actor`): One Euro filter per joint, pose classifiers (rule-based, pure functions → unit-testable), motion classifier (Core ML `MLModel` hand action classifier over a sliding 1–1.5 s window, optional), arm/disarm state machine, guards.
- **IntentRouter** (`actor`): 
  - *Fast path* (cursor, click, drag, scroll, volume dial): direct to executor, never touches the LLM.
  - *Mapped path*: discrete gesture → user mapping (+ per-app override) → action.
  - *Smart path*: smart gesture → `LanguageModelSession` with tools (each executable action is a `Tool`) and `@Generable ActionResolution` given frontmost app bundle ID/name; result cached per app for the session.
  - *Fallback*: if `SystemLanguageModel.default.availability != .available` (or timeout 1.5 s / error), a built-in rule table maps bundle IDs → actions.
- **Configuration** (`@MainActor @Observable` settings store, JSON in Application Support): NL config via FM guided generation producing `@Generable GestureMapping` → validated against known gestures/actions before saving, shown to user for confirmation.
- **ActionExecutor** (`actor` for AppleScript/App Intents; CGEvent posting on a dedicated serial executor): CGEvent mouse/scroll/keyboard + media/volume system-defined key events; `NSAppleScript`/`NSWorkspace` for app-level; App Intents exposes Palmo's own actions (Arm, Disarm, Toggle overlay) to Shortcuts.
- **UI** (`@MainActor`): MenuBarExtra (status, arm toggle, settings), Settings window, onboarding (Camera + Accessibility with denied-state cards and "Open System Settings" deep links), optional floating overlay (`NSPanel`, non-activating, click-through) showing hand skeleton/state, data-collection mode for training.

Data flow: frames (CVPixelBuffer, not crossing actors) → `HandObservation` (Sendable) via `AsyncStream` → `GestureEvent` → `Intent` → `Action`.

Latency budget (target, 30 fps, Apple Silicon):
| Stage | Budget |
|---|---|
| Capture + frame delivery | ~33 ms (frame interval) |
| Vision hand pose | 8–15 ms |
| Filtering + rules | < 1 ms |
| Fast path execute (CGEvent) | < 2 ms |
| **Cursor motion-to-photon** | **≈ 50–60 ms** |
| Discrete gesture (incl. dwell) | 150–400 ms |
| Smart path (FM, warm session) | 300–1500 ms (prewarmed, cached per app; fallback on timeout) |

Energy: 10 fps + skip Vision when no hand for 2 s (cheap frame-difference check); stop capture entirely when disarmed for N minutes except a low-rate "arm watch" mode (configurable: ~5 fps); pause capture on Low Power Mode (`NSProcessInfoPowerStateDidChange`), on screen lock/sleep, and when display is off; FM session prewarmed only once armed.

Threading rules: no `@unchecked Sendable` except the AV delegate bridge (documented); UI only on MainActor; CGEvent posting off main.

## 4. Training (Core ML)
In-app **Data Collection mode** records labelled hand-pose keypoint sequences (JSON / MLMultiArray-compatible) per motion gesture into `~/Library/Application Support/Palmo/Training/`. TRAINING.md will explain training a **Create ML Hand Action Classifier** (Create ML app, or `CreateMLComponents` script) and dropping `PalmoMotion.mlmodelc` into the model folder. Without a model, rule-based motion detectors are used.

## 5. Verification Notes (APIs to confirm while building)
- `FoundationModels`: exact signatures for `Tool` protocol (`call(arguments:)` return type in SDK 26.5), `@Generable`/`@Guide` macros, `LanguageModelSession(tools:instructions:)`, `prewarm()`, and error types — will be checked by compiling against the SDK, not assumed.
- Create ML **Hand Action Classifier** input shape (frames × 3 × 21 keypoints) and expected frame rate when loading via Core ML outside Vision.
- Media/volume keys: posting `NX_KEYTYPE_PLAY/SOUND_UP` via `NSEvent.otherEvent(.systemDefined, subtype 8)` → `cgEvent.post` is public API but behaviour on macOS 26 needs testing.
- Space switching via Ctrl+←/→ and Mission Control key codes depend on user's keyboard-shortcut settings (fallback: launch Mission Control app via `NSWorkspace`).
- `NSAppleScript` targeting other apps requires `NSAppleEventsUsageDescription` and per-app Automation consent.
- Whether `AVCaptureDevice` on macOS 26 offers reduced-fps formats for the built-in camera (else drop frames in software).
- Low Power Mode on macOS: `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange` (available on macOS 12+).
- Continuity Camera can appear as a camera — the device picker will default to built-in.

## 6. App Store blockers
- **Sandbox vs. CGEvent posting:** synthetic input into other apps requires Accessibility trust; sandboxed apps can request it (`AXIsProcessTrustedWithOptions`), but App Review routinely rejects apps whose core function is controlling other apps/input — high rejection risk. Palmo ships **unsandboxed**, Developer-ID-style (not possible on a free account; local use only).
- **AppleScript to arbitrary apps:** sandbox requires `com.apple.security.temporary-exception.apple-events` or `scripting-targets` per app — App Review rarely grants temporary exceptions for arbitrary apps.
- **Space switching/Mission Control** via synthetic keys works only unsandboxed with Accessibility.
- **Free account:** no notarization/Developer ID; distribution to others requires a paid account.
- No private APIs will be used.

## 7. Roadmap (post-v1)
Two-hand gestures (zoom/rotate), per-user calibration wizard, eye/head-gaze cursor assist, Shortcuts-defined custom actions, on-device personalised classifier fine-tuning, multi-display cursor mapping.
