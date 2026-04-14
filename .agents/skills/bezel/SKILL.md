---
name: bezel
description: >-
  Apple device framing CLI. Use when wrapping raw simulator screenshots or PNG
  assets inside official Apple device bezels (iPhone, iPad, Apple Watch), when
  producing marketing or App Store hero images, landing page screenshots,
  OG images, or any composite that needs a real device frame around a capture.
  Also use when the user asks to "frame", "bezel", "mock up", or "render in a
  device" an existing screenshot, or to capture and frame directly from the
  booted simulator in one step.
allowed-tools: Bash, Read
---

# bezel - Apple Device Framing

## Bootstrap (First-Run)

Before using any `bezel` command, verify the tool is available. If not, build and install it from this repo checkout.

```bash
# 1. Check if bezel is installed
if ! command -v bezel >/dev/null 2>&1; then
  # 2. Build release binary and install
  swift build -c release
  mkdir -p ~/.local/bin
  cp .build/release/bezel ~/.local/bin/
fi

# 3. Verify setup
bezel assets status
```

If `~/.local/bin` is not in PATH, tell the user to add `export PATH="$HOME/.local/bin:$PATH"` to `~/.zshrc`.

On first run the asset catalog will be missing. Sync it once:

```bash
bezel assets sync apple --platform iphone --platform watch --platform ipad
```

This downloads Apple Design Resources DMGs into `~/Library/Caches/bezel/apple/`, mounts them, extracts the PNG bezels, detects the transparent aperture for each frame, and writes `catalog.json`. Apple assets are **not** redistributed by this repo — they are fetched directly from `devimages-cdn.apple.com`.

## Architecture

`bezel` is a Swift CLI (ArgumentParser-based) that:

- **Downloads and caches** official Apple bezel PNGs from Apple Design Resources DMGs
- **Detects the device aperture** (the transparent screen cutout) per frame and stores a mask
- **Auto-resolves device + style** from a screenshot by matching aspect ratio against the catalog, or from the booted simulator's name
- **Composites** the screenshot into the frame's aperture with a small bleed under the anti-aliased edge, then optionally adds a soft shadow, background color, padding, and a target canvas size
- **Captures from the booted simulator** via `xcrun simctl io … screenshot` when `--from-sim` is passed

Asset cache root: `~/Library/Caches/bezel/apple/` (contains `downloads/`, `extracted/`, `metadata/`, `catalog.json`).

## Quick Reference

### Top-level commands

| Command | Description |
|---------|-------------|
| `bezel frame …` | Frame a PNG (or simulator capture) inside a device bezel (default subcommand) |
| `bezel assets sync apple …` | Download + catalog Apple bezel assets |
| `bezel assets status` | Show local asset cache status |
| `bezel devices` | List cached devices and available styles |
| `bezel presets` | List built-in export presets |

### `bezel frame` flags

| Flag | Description |
|---|---|
| `<input.png>` (positional) | Path to a screenshot PNG. Omit when using `--from-sim`. |
| `--from-sim` | Capture a raw screenshot from the booted simulator before framing |
| `--udid <UDID>` | Target a specific booted simulator for `--from-sim` |
| `--device <id>` | Force a specific device id (see `bezel devices`) |
| `--style <name>` | Force a specific device style/finish (e.g. `silver`, `space-black`) |
| `--orientation <portrait\|landscape>` | Force orientation instead of auto-detecting from image aspect |
| `-o, --output <path>` | Output PNG path (defaults to `<input>-framed.png`, or `./bezel-<ts>.png` for `--from-sim`) |
| `--background <transparent\|#RRGGBB>` | Background fill (default: `transparent`) |
| `--padding <int>` | Pixels of padding around the device on the final canvas (default: `0`) |
| `--shadow` / `--no-shadow` | Soft drop shadow beneath the device (default: **on**) |
| `--canvas <WxH>` | Final canvas size in pixels; device is centered and fit inside |
| `--preset <name>` | Named export preset (overrides `--canvas`/`--background`/`--padding`) |
| `--json` | Emit machine-readable JSON (`{output, device, style}`) |

When no `--canvas` is set and `--shadow` is on, bezel auto-insets 48px to keep the shadow from clipping at the edge.

### Built-in presets

Run `bezel presets` for the live list. Built-ins defined in `Sources/bezel/Core/Presets.swift`:

| Preset | Canvas | Background | Padding |
|---|---|---|---|
| `appstore-phone-tall` | 1320×2868 | transparent | 0 |
| `landing-hero` | 2400×1600 | solid | 240 |
| `og-image` | 1200×630 | solid | 80 |
| `social-square` | 1080×1080 | transparent | 120 |

Presets with `background: solid` need `--background '#RRGGBB'` to be set explicitly when invoking — the preset supplies the canvas/padding, the caller supplies the color.

### Device resolution

`bezel frame` resolves the device/style in this order:

1. **Explicit** `--device` (and optional `--style`) — hard match against catalog
2. **Simulator name** (when `--from-sim`) — looks up `simulatorNames` in the catalog
3. **Aspect ratio match** against cached aperture rects (tolerance 0.015). If exactly one device matches, uses it; otherwise errors with candidate list and asks for `--device`.

Default style per device is picked from a preferred-rank table (e.g. `silver` > `space-black` > `black`). Use `--style` to override.

## Common Patterns

### Frame the current simulator in one step

```bash
bezel frame --from-sim --output /tmp/hero.png
```

Captures from the booted iPhone/iPad/Watch (preferring iPhone), auto-detects the device from the simulator name, frames it with the default shadow, writes `/tmp/hero.png`.

### Landing-page hero with solid background

```bash
bezel frame --from-sim \
  --shadow \
  --background '#F5F5F7' \
  --padding 120 \
  --output /tmp/hero.png
```

### Frame an existing screenshot with a forced device + finish

```bash
bezel frame screenshot.png \
  --device iphone-17-pro \
  --style silver \
  --output /tmp/output.png
```

### App Store screenshot (exact 1320×2868 canvas)

```bash
bezel frame screenshot.png --preset appstore-phone-tall --output /tmp/appstore.png
```

### OG image with brand background

```bash
bezel frame screenshot.png \
  --preset og-image \
  --background '#0B0B0F' \
  --output /tmp/og.png
```

### Pair with `sim` to capture + frame

```bash
sim screenshot                                   # raw capture via sim skill
bezel frame /path/from/sim-screenshot.png \      # then frame it
  --preset landing-hero \
  --background '#FFFFFF' \
  --output /tmp/landing.png
```

Or skip the intermediate file entirely with `bezel frame --from-sim`.

### Inspect available devices and styles

```bash
bezel devices            # human
bezel devices --json     # machine-readable
```

### Get structured output for scripting

```bash
bezel frame screenshot.png --json
# {"device":"iphone-17-pro","output":"/…/screenshot-framed.png","style":"silver"}
```

## Error Recovery

| Error | Fix |
|---|---|
| `Catalog: missing` | Run `bezel assets sync apple --platform iphone …` to populate `~/Library/Caches/bezel/apple/` |
| `No matching frame found for image ratio <r>` | Screenshot aspect doesn't match any cached aperture. Pass `--device` explicitly, or sync more platforms. |
| `Ambiguous device for this screenshot. Pass --device. Candidates: …` | Multiple devices share that aspect ratio. Pick one with `--device <id>` from the printed list. |
| `No cached frame found for <device> / <orientation>` | That device isn't in the catalog for that orientation. Run `bezel devices` to see what is cached; re-sync if needed. |
| `No booted simulator found` (with `--from-sim`) | Boot a simulator first (e.g. `sim boot "iPhone 16 Pro"` or via Xcode), then retry. Pass `--udid` to target a specific one. |
| `Only the apple provider is supported.` | `bezel assets sync` currently only accepts `apple` as the provider argument. |
| `Unknown preset '<name>'.` | Run `bezel presets` for the valid list. |
| `Invalid canvas '<raw>'. Expected WxH.` | Canvas must be `WIDTHxHEIGHT` in pixels, e.g. `--canvas 2400x1600`. |
| `Unknown platform '<x>'` | Valid platforms are `iphone`, `watch`, `ipad`. |
| DMG download fails | The tool `curl`s Apple Design Resources DMGs. Check network + that `hdiutil` can mount; re-run `bezel assets sync apple`. |

## Implementation Pointers

Useful entry points when debugging or extending:

- `Sources/bezel/main.swift` — CLI root and subcommand registration
- `Sources/bezel/Commands/FrameCommand.swift` — `frame` argument surface
- `Sources/bezel/Core/Compositor.swift` — the actual render pipeline (mask clip, bleed, shadow, canvas)
- `Sources/bezel/Core/DeviceDetector.swift` — device/style auto-resolution rules
- `Sources/bezel/Core/AssetProvider.swift` — DMG download, mount, aperture detection, catalog build
- `Sources/bezel/Core/SimulatorBridge.swift` — `simctl` capture for `--from-sim`
- `Sources/bezel/Core/Presets.swift` — built-in export presets
