# Gestures

Palmo tracks one hand: the one closest to the camera, with the highest confidence. All rules use
**hand-relative** measurements, normalized by palm size and palm orientation. So they work at any distance
from the camera, with either hand, and with the hand tilted.

## Arming

Palmo does nothing until you arm it. This keeps everyday hand movement from triggering actions.

| | Gesture | Rule |
|---|---|---|
| ✋ **Arm** | Open palm toward the camera, held 0.8 s | All four fingers extended, thumb out, fingers fanned |
| ✊ **Disarm** | Fist held 1 s | All four fingers curled, thumb tucked |

Palmo also disarms automatically:

- after the idle timeout (default 20 s with no gesture, including when your hand leaves the frame);
- from the menu, Shortcuts or the App Intent;
- when the camera pauses for screen sleep, screen lock or Low Power Mode.

While you are typing (within 0.6 s of a key press), Palmo neither arms nor fires gestures. A hand overlapping
your face is ignored.

## Fast-path gestures (always on, not rebindable)

| | Gesture | Rule | Action |
|---|---|---|---|
| ☝️ | **Point and move** | Index extended, others curled | Relative pointer motion, steered by your index and middle knuckles by default. Slow motion is scaled down for precision and quick motion accelerates. Smoothing removes jitter when the hand is nearly still. To reposition ("clutch"), relax the index or drop the hand, move, and point again. |
| 🤏 | **Pinch click** | Thumb tip meets index tip, released within 0.3 s | Click. Two clicks within 0.4 s make a double-click. The cursor freezes as the thumb approaches and for 0.2 s after release, and clicks just off a button snap onto it. |
| 🤏➡️ | **Pinch drag** | Pinch held longer than 0.3 s | Mouse down, drag with hand motion, mouse up on release. |
| 🤌 | **Middle pinch** | Thumb meets middle finger while the index stays up | Right-click |
| ✌️↕️ | **Two-finger scroll** | Index and middle extended together | Scroll follows hand motion, natural direction |
| 🤏🔄 | **Volume dial** | Index pinch with middle, ring and little extended; rotate like a knob | One volume step about every 12° |

Pinches use **hysteresis**: they start when the gap drops below the enter threshold and end only when it rises
above a wider exit threshold. This stops a borderline pinch from flickering on and off.

## Discrete gestures (rebindable)

| | Gesture | Rule | Default | Cooldown |
|---|---|---|---|---|
| 👋⬅️ | **Swipe left** | Open hand moves fast to the left (≥ 3 samples in 0.45 s) | Next Space | 0.8 s |
| 👋➡️ | **Swipe right** | Same, to the right | Previous Space | 0.8 s |
| 🤟⬆️ | **Three-finger flick up** | Index, middle and ring up; flick up | Mission Control | 1.0 s |
| 🤟⬇️ | **Three-finger flick down** | Same, down | App Exposé | 1.0 s |
| 👍➡️ | **Thumb flick right** | Fist with thumb out; flick right | Next app (⌘-Tab) | 0.5 s |
| 👍⬅️ | **Thumb flick left** | Same, left | Previous app | 0.5 s |
| 👍 | **Thumbs up** | Fist with thumb pointing up, held 0.5 s | Play / pause | 1.5 s |
| ✌️👉 | **Peace flick right** | V sign (fingers spread); flick right | Next track | 0.8 s |
| ✌️👈 | **Peace flick left** | Same, left | Previous track | 0.8 s |
| 🖐️🔁 | **Palm flip (smart)** | Open hand turns to the back and returns within 0.7 s | Smart: depends on the app | 1.2 s |

Directions are as you see them in a mirror. "Right" means toward your right.

### The smart gesture

When a gesture is mapped to **Smart**, Palmo asks the on-device model which action fits the frontmost app. It
caches the answer per app until settings change. If the model is unavailable or takes longer than 1.5 s, these
rules apply:

| App | Action |
|---|---|
| Safari, Chrome, Firefox, Arc, Edge | Reload page |
| Keynote, PowerPoint, Preview | Next slide |
| Music, Spotify | Next track |
| Podcasts, TV, QuickTime Player | Play / pause |
| Xcode | Run (⌘R) |
| Zoom, FaceTime, Teams | Toggle meeting mute (⇧⌘M) |
| Finder | Quick Look |
| Anything else | Mission Control |

## Customizing

- **Settings → Gestures:** turn each gesture on or off, and pick its action.
- **Settings → Apps:** per-app overrides for the frontmost app, or any app you add.
- **Settings → Ask:** plain-English requests, such as "make thumbs up pause my music" or
  "in Keynote, swipe left should go to the next slide". Apple Intelligence is used when available, otherwise a
  rule parser. Palmo shows the change it made and which engine interpreted the request.
- **Shortcuts:** the *Configure Palmo Gesture* intent does the same (see Verification Notes about Shortcuts
  discovery).

### Sensitivity and pointer speed

- **Sensitivity** (0.5–1.5) scales the pinch thresholds, the curl and extension thresholds, and the motion
  distances. Higher means easier to trigger.
- **Pointer speed** (0.5–3.0) scales the cursor gain.
- **Fine control when moving slowly** (0.15–1, default 0.35): the pointer speed for slow hand motion, as a
  fraction of normal. Lower is finer. 1 turns the precision zone off.
- **Acceleration for fast moves** (0–4, default 1.6): the extra speed a quick flick gets.
- **Jitter smoothing** (0–1, default 0.5): higher is steadier when still, with slightly more lag. 0 is off.
- **Pointer follows:** *Knuckles* (default) barely moves when you pinch, so clicks don't drift. *Fingertip* is
  more direct.
- **Snap clicks onto nearby buttons** (default on): before clicking, Palmo asks Accessibility for a clickable
  control within about 14 pt of the cursor and moves onto it. Window close, minimize and zoom buttons get a
  larger radius (about 21 pt).

### Closing and minimizing windows

The **Close window** and **Minimize window** actions press the focused window's own close or minimize button
through Accessibility, falling back to ⌘W or ⌘M. Map them to any discrete gesture. Smart gestures never pick
them, so a window is never closed by surprise.

If you get false triggers, lower the sensitivity, raise the typing guard, or turn off the gestures you don't use.

## Core ML motion model (optional)

If `~/Library/Application Support/Palmo/Models/PalmoMotion.mlmodel` (or `.mlmodelc`) exists, Palmo runs it
alongside the rules. A prediction with confidence ≥ 0.85 for an enabled motion gesture fires that gesture, with
the same cooldowns. A *background* prediction never fires anything. See [TRAINING.md](TRAINING.md).
