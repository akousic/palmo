# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-10-29

### Changed
- **Arming is much more reliable.** The open-palm hold now uses its own forgiving palm check (a relaxed hand with
  fingers less fanned or the thumb part-way in still counts) and a dropout-tolerant timer. Missed or misread frames
  pause the hold for up to 0.4 s instead of restarting it. The hold is 0.7 s and needs at least 4 qualifying frames.
- The camera runs at 30 fps whenever a hand is in view, armed or not (previously 15), and at 8 fps when idle (previously 6).
- The enlarged face zone now applies only while armed, so a palm raised beside the face can arm.
- When two hands are visible, Palmo tracks the raised one, so a hand resting on the keyboard no longer hides it.

### Added
- *Arm gesture forgiveness* slider (Settings → Feel).
- Arming progress ring in the overlay, a menu-bar icon change while arming, and the reason a palm isn't counting
  shown in the menu.
- Global **⌃⌥⌘P** shortcut that toggles Armed. It needs no extra permission.
- Privacy-safe arming diagnostics through `os.Logger` (subsystem `com.kousic.palmo`, category `arming`).

## [0.2.0] - 2026-10-29

### Added
- Precision pointer curve: slow hand motion is scaled down (Settings → Feel → *Fine control*, default 0.35×)
  and fast motion accelerates (*Acceleration*, default +1.6×).
- A dedicated pointer jitter filter (*Jitter smoothing*) and a smaller dead zone.
- *Pointer follows* setting. The new default, the index and middle knuckles, stays put while you pinch.
- The cursor freezes while a pinch forms, while it is held before a drag starts, and for 0.2 s after release.
- *Snap clicks onto nearby buttons*: Accessibility hit-testing moves a click onto a control within about 14 pt,
  or about 21 pt for window buttons.
- **Close window** and **Minimize window** actions, which press the focused window's buttons (⌘W/⌘M fallback),
  with Ask phrases such as "thumbs up closes the window".
- `scripts/build-app.sh` installs to `/Applications/Palmo.app`. It quits a running Palmo and relaunches it.
  Use `--no-install` to skip.

### Changed
- Settings decode missing keys with defaults, so upgrading keeps existing mappings.

## [0.1.0] - 2026-10-28

### Added
- Menu bar app (`MenuBarExtra`) with status, arm/disarm, a pause toggle, settings and onboarding with
  granted/denied permission states.
- Camera capture with Vision hand-pose tracking, face-zone rejection and adaptive frame rate (30/15/6 fps).
- One Euro smoothing, a scale- and rotation-invariant pose classifier, and a gesture state machine with arming,
  dwell, debounce, hysteresis and per-gesture cooldowns.
- 18 gestures:
  - arm and disarm;
  - point, pinch click, double-click and drag, middle-pinch right-click, two-finger scroll and volume dial;
  - swipes, three-finger flicks, thumb flicks, thumbs up and peace flicks;
  - the smart palm flip.
- Fast-path execution through CGEvent, plus media keys, Spaces, Mission Control, App Exposé and the app switcher.
- AppleScript actions for Music, Spotify and Keynote.
- Mappings: per-gesture enable, global mappings and per-app overrides.
- Foundation Models: tool-calling context resolution (one tool per action) with a 1.5 s timeout, a cache and a
  rule fallback.
- Natural-language configuration using guided generation (`@Generable`), with a rule-based parser fallback.
- Training clip recorder in the Create ML folder layout, and an optional Core ML motion classifier.
- App Intents: Arm, Disarm, Set Tracking and Configure Gesture.
- Hand overlay panel, idle auto-disarm, typing guard, and pausing on screen sleep, screen lock and Low Power Mode.
- `scripts/build-app.sh` builds a signed app bundle with the hardened runtime.
- Swift Testing suites for recognition, filtering, mapping, intent routing and Foundation Models.
