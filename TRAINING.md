# Training a motion classifier

Palmo's rules handle every gesture without a model. A **Create ML Hand Action Classifier** trained on your own
clips can make motion gestures more reliable for your hands, camera and lighting. Palmo runs it alongside the
rules.

## 1. Record clips in Palmo

1. Open Settings → **Training**.
2. Pick a label, then click **Record 2.5 s Clip**. Palmo records a 2.5 s clip from the same camera feed it
   uses for tracking. Tracking keeps running during the recording.
3. Clips are saved as H.264 `.mov` files in Create ML's folder-per-label layout:

   ```
   ~/Library/Application Support/Palmo/Training/
     swipeLeft/swipeLeft-1761700000000.mov
     swipeRight/…
     threeFingerUp/  threeFingerDown/  thumbFlickLeft/  thumbFlickRight/
     peaceFlickLeft/ peaceFlickRight/  palmFlip/
     background/     ← required negative class
   ```

   *Show in Finder* opens the folder. The tab shows a clip count for each label.

**How many:** aim for at least 30 clips per label, and 60+ for *background*.

- Vary distance, angle, lighting, speed and both hands.
- Each clip should contain one gesture, roughly centered in time.
- *background* should cover everything that is not a gesture: typing, reaching for the trackpad, touching your
  face, waving at someone, an empty frame, holding a mug. It matters most for keeping false triggers down.

## 2. Train in Create ML

1. Open **Create ML** (Xcode → Open Developer Tool → Create ML). Choose **New Document → Hand Action
   Classification**.
2. **Training Data:** drag in the `Training` folder.
   **Validation:** *Automatic*, or a separate folder recorded on another day.
3. **Parameters:**
   - **Action duration:** 1.0 s. Palmo's motion window is about 0.45 s, but a slightly longer window gives
     the model context. Palmo reads the model's required frame count from its input shape, so any length
     works.
   - **Frame rate:** 30. This matches Palmo's armed frame rate.
   - **Augmentations:** turn on horizontal flip *only* if you don't care about left versus right. Flipping
     swaps swipeLeft and swipeRight, so normally leave it off. Rotate and scale are fine.
4. **Train.** Check per-class precision on the Evaluation tab. If *background* is often confused with a gesture,
   record more *background* clips.
5. **Preview:** test with a new clip.

## 3. Install the model

Export the model and name it **`PalmoMotion.mlmodel`**, then copy it to:

```
~/Library/Application Support/Palmo/Models/PalmoMotion.mlmodel
```

Palmo compiles it on load. You can also place a compiled `PalmoMotion.mlmodelc` there. In Settings → Training,
click **Reload Model**. The tab then shows whether a model is loaded. Load errors appear in the menu.

## Input contract

| | |
|---|---|
| Input | MLMultiArray of shape `[frames, 3, 21]`: (x, y, confidence) for the 21 Vision hand joints |
| Joint order | Create ML's hand-pose order: wrist, thumb CMC→tip, index MCP→tip, middle, ring, little |
| Coordinates | Vision normalized image coordinates (origin bottom-left), unmirrored |
| Output | Class label plus probabilities. Labels must match `Gesture` raw values (`swipeLeft` …) or `background` |

Palmo mirrors x for display and for its rules. Before prediction it un-mirrors the poses, so the model sees the
same coordinates Create ML extracted during training.

## How predictions are used

- **Threshold:** a prediction fires only if the label is an enabled gesture and the confidence is ≥ 0.85.
- **Cooldown:** model and rule detections share the per-gesture cooldown, so one motion cannot fire twice.
- **Gating:** the model never arms or disarms Palmo, and it is ignored while you type or while the hand
  overlaps your face.
