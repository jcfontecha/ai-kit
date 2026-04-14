---
name: onboarding-video-pipeline
description: Process, trim, and bundle stock video clips for the onboarding carousel. Use when the user provides raw video files to select from, replace, or add onboarding videos.
---

# Onboarding Video Pipeline

Process raw stock footage into optimized looping clips for the onboarding carousel.

## When to Use

- User provides new stock video files to evaluate
- User wants to replace or add an onboarding video
- User wants to preview/compare video options

## Current Setup

Videos live at: `apps/ios/Kauch/Features/Onboarding/`

| File | Screen | Description |
|------|--------|-------------|
| `onboarding-track.mp4` | Screen 1 | Equipment-focused |
| `onboarding-coach.mp4` | Screen 2 | Exercise catalog |
| `onboarding-progress.mp4` | Screen 3 | Generation / AI |
| `onboarding-sources.mp4` | Screen 4 | Training philosophy |

Screen mapping is defined in `OnboardingItem.swift` via the `videoName` field.

## Encoding Spec

All onboarding videos must match this spec:

| Parameter | Value |
|-----------|-------|
| Resolution | 720x1280 (portrait) |
| Codec | H.264 |
| Bitrate | 2 Mbps |
| Frame rate | 30 fps |
| Audio | None (stripped) |
| Duration | 6 seconds |
| Container | MP4 with faststart |

Target file size: ~1.3-1.5 MB per clip.

## Workflow

### 1. Evaluate raw clips

Extract thumbnail frames at multiple timestamps to assess content:

```bash
for t in 0 3 5 7 10; do
  ffmpeg -y -ss $t -i "$INPUT" -frames:v 1 -q:v 2 "/tmp/thumb_t${t}.jpg" 2>/dev/null
done
```

Read the thumbnails to evaluate framing, lighting, and subject.

### 2. Selection criteria

- **Dark/cinematic lighting preferred** — matches the onboarding's dark UI and gradient overlays
- **Clear subject** — avoid too-tight crops or overly blurry shots
- **Movement** — the clip should have visible motion for the looping video player
- **Diversity** — vary subjects (gender, exercise type, equipment) across screens
- **Visual cohesion** — similar color grade across all clips (the Videophilia Artlist set has a consistent dark cinematic look)

### 3. Encode

```bash
ffmpeg -y -ss $START_TIME -t 6 \
  -i "$INPUT" \
  -c:v h264 -b:v 2M -an -r 30 \
  -vf "scale=720:1280" \
  -movflags +faststart \
  "$OUTPUT"
```

- Choose `-ss` carefully — find a 6-second window with good motion and framing
- Do NOT apply color grading filters (e.g., `curves`) — the card's gradient overlay handles contrast
- Verify output: `ffprobe -v quiet -show_entries format=duration -show_entries stream=width,height -of csv=p=0 "$OUTPUT"`

### 4. Verify uniqueness

```bash
md5 -q video1.mp4 video2.mp4
```

Ensure no two onboarding videos have the same hash.

### 5. Add to project

Place the encoded `.mp4` in `apps/ios/Kauch/Features/Onboarding/`. The Xcode project uses folder-based references (objectVersion 77), so new files in the directory are automatically included in the bundle.

If adding a new screen (not replacing), also update `OnboardingItem.screens` in `OnboardingItem.swift`.

### 6. Test

- Run `make build` to verify compilation
- Uninstall and reinstall the app on the simulator to see changes (video assets are bundled at install time)
- The `LoopingVideoPlayerView` falls back to a dark gray background if the video file is missing

## Gotchas

- **UserDefaults caching on iOS 26 simulators**: `defaults write/delete` does not reliably reset `@AppStorage` flags. To re-show onboarding, uninstall and reinstall the app via `xcrun simctl uninstall booted com.fontecha.Kauch`
- **Bundle caching**: `simctl install` is required after rebuilding for new video assets to appear — `simctl launch` alone reuses the old bundle
- **No darkening filters**: The `OnboardingCardView` already applies a bottom gradient overlay (`black.opacity(0.6)` to `clear`). Adding extra darkening via ffmpeg `curves` can make clips appear black
