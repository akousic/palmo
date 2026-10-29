# Privacy

Palmo runs entirely on your Mac.

**What it sees.** Camera frames are processed in memory by Apple's Vision framework to find hand and face
positions. A frame is discarded as soon as its landmarks are extracted. Palmo keeps only the last few hand poses
(about one second), in memory, for motion detection.

**What it stores.**

- **Settings:** your gesture mappings, per-app overrides and preferences, stored in `UserDefaults`
  (`com.kousic.palmo`).
- **Training clips** you record yourself, in `~/Library/Application Support/Palmo/Training`. Palmo only records
  when you click *Record 2.5 s Clip* in Settings → Training. Delete clips in Finder at any time.
- **A motion model** you install, in `~/Library/Application Support/Palmo/Models`.

Palmo does not store video, images, hand data, keystrokes or usage logs anywhere else.

**What it sends.** Nothing. Palmo contains no networking code, analytics, crash reporting or third-party SDKs.
Apple Intelligence requests use Foundation Models' **on-device** system model. The prompts contain only the
gesture name, the frontmost app's name and bundle identifier, the list of candidate actions, or the
configuration sentence you typed.

**Permissions and why.**

| Permission | Used for |
|---|---|
| Camera | Seeing your hand. The green camera light is on whenever tracking runs. Pause it from the menu at any time. |
| Accessibility | Posting pointer, click, scroll and keyboard events. Palmo does not read screen contents or other apps' UI. |
| Automation (Apple Events) | Sending fixed commands (play/pause, next track, slideshow controls) to Music, Spotify and Keynote. Asked per app. |

**Keyboard.** To pause gestures while you type, Palmo checks *how long ago* a key was pressed, using
`CGEventSource.secondsSinceLastEventType`. It never sees which keys were pressed.

**Frontmost app.** Palmo reads the frontmost app's name and bundle ID, for per-app overrides and the smart
gesture. They stay in memory and are never logged.
