# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
