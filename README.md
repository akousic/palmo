# Palmo

Control your Mac with hand gestures. Palmo is a menu bar app that watches one hand through the built-in
camera and turns gestures into pointer movement, clicks, scrolling, volume, Spaces, media and app actions.
Everything runs on your Mac: Vision does the hand tracking, Core ML runs an optional motion classifier you
train yourself, and Apple Intelligence (Foundation Models) handles natural-language setup and the
context-aware "smart" gesture.

- **Swift 6, SwiftUI `MenuBarExtra`, macOS 26+, built with Swift Package Manager.** No Xcode project.
- **Fast path that never touches the language model:** point, pinch-click, drag, right-click, scroll and volume
  go straight from the gesture recognizer to `CGEvent`.
- **The model only resolves the smart gesture and configuration.** It has a 1.5 s timeout and a rule-based
  fallback, so Palmo works fully without Apple Intelligence.
- **Privacy:** no network code and no analytics. Video is never stored, except the training clips you record
  yourself. See [PRIVACY.md](PRIVACY.md).

## Requirements

- macOS 26 or later on Apple silicon, with a built-in or external camera.
- Xcode 26 command-line tools (Swift 6.2+). Developed against SDK 26.5 with Swift 6.3.
- Optional: Apple Intelligence turned on, for natural-language mapping and the smart gesture.

## Build and run

```sh
swift test                 # unit tests (Swift Testing)
scripts/build-app.sh       # release build → build/Palmo.app, signed with your Apple Development identity
open build/Palmo.app
```

`build-app.sh` uses the first "Apple Development" identity in your keychain. To pick one explicitly, pass
`--identity "Apple Development: you@example.com (TEAMID)"` or set `PALMO_SIGN_IDENTITY`. If no identity is
found, it signs ad hoc. In that case macOS forgets the Accessibility grant on every rebuild.

### First launch and permissions

1. Open `build/Palmo.app`. A hand icon appears in the menu bar (there is no Dock icon) and onboarding opens.
2. **Camera:** click *Allow Camera* and confirm the system prompt. If you denied it earlier, use
   *Open Camera Settings*, then go to Privacy & Security → Camera and turn on Palmo.
3. **Accessibility** (needed to move the pointer, click and press keys): click *Open Accessibility Settings*,
   turn on Palmo under Privacy & Security → Accessibility, then return to Palmo. Onboarding notices the change
   automatically.
4. **Automation** (optional; needed only for Music, Spotify and Keynote actions): macOS asks the first time
   Palmo controls each app.
5. Hold an **open palm** toward the camera for about a second to arm. Make a **fist** and hold it to disarm.

If Accessibility shows as on but nothing happens after a rebuild, remove Palmo from the Accessibility list
with the – button and add it again. This happens when the signature changes, for example after an ad-hoc build.

## Gestures

| Gesture | Default action |
|---|---|
| ✋ Open palm hold | Arm |
| ✊ Fist hold | Disarm |
| ☝️ Point and move | Move the pointer |
| 🤏 Pinch (quick / twice / hold) | Click / double-click / drag |
| 🤌 Middle-finger pinch | Right-click |
| ✌️↕️ Two fingers up, move | Scroll |
| 🤏🔄 Pinch with other fingers up, rotate | Volume |
| 👋⬅️ / 👋➡️ Open-hand swipe | Next / previous Space |
| 🤟⬆️ / 🤟⬇️ Three-finger flick | Mission Control / App Exposé |
| 👍⬅️ / 👍➡️ Thumb flick | Switch app |
| 👍 Thumbs up | Play / pause |
| ✌️👉 / ✌️👈 Peace flick | Next / previous track |
| 🖐️🔁 Palm flip | Smart: depends on the frontmost app |

See [GESTURES.md](GESTURES.md) for details and tuning. You can rebind any discrete gesture under
Settings → Gestures, override it per app under Settings → Apps, or type a request in Settings → Ask, such as
"in Keynote, palm flip should start the slideshow".

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md): the pipeline, concurrency and module map
- [GESTURES.md](GESTURES.md): the gesture vocabulary, detection rules and tuning
- [TRAINING.md](TRAINING.md): recording clips and training the Create ML motion classifier
- [PRIVACY.md](PRIVACY.md): what Palmo sees, stores and never sends
- [CONTRIBUTING.md](CONTRIBUTING.md), [CHANGELOG.md](CHANGELOG.md), [ROADMAP.md](ROADMAP.md)
- [docs/VERIFICATION-NOTES.md](docs/VERIFICATION-NOTES.md): what was verified and how, and what still needs a manual check
- [docs/APP-STORE-BLOCKERS.md](docs/APP-STORE-BLOCKERS.md): what stands between Palmo and the Mac App Store
- [docs/DESIGN-SUMMARY.md](docs/DESIGN-SUMMARY.md): the original approved design

## License

MIT.
