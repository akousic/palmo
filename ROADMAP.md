# Roadmap

Rough priorities, not promises.

## Next (0.2)
- **Bundled starter motion model.** Train it on clips recorded with consent from several people, so the Core ML
  path helps out of the box.
- **Calibration wizard.** A one-minute guided session that measures your pinch gap and finger extension and
  tunes thresholds per user.
- **Shortcuts discovery.** Generate App Intents metadata (`Metadata.appintents`) in the SwiftPM build, or add a
  thin Xcode app target, so Palmo's intents show up in Shortcuts and Spotlight.
- **Gesture practice view.** Live feedback showing which shape Palmo sees and how close each gesture is to firing.
- **Map gestures to user Shortcuts.** Use any shortcut as a target action.

## Later
- Two-hand gestures: zoom and rotate.
- Per-app gesture sets that switch automatically, such as a presentation mode.
- Continuity Camera and external camera selection in Settings.
- Accessibility profiles for limited mobility: larger dwell times, single-gesture scanning mode.
- Localization.

## Exploring
- A Mac App Store build (see [docs/APP-STORE-BLOCKERS.md](docs/APP-STORE-BLOCKERS.md)).
- Developer ID signing and notarization for direct distribution. This needs a paid developer account.
- Using hand depth (where available) for push-to-click.
