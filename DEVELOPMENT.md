# Castle Development

## Run in Dev Mode

```bash
cd /Users/danielnguyen/Castle
swift run
```

## Build

```bash
cd /Users/danielnguyen/Castle
swift build
```

## Build Launchable App

```bash
cd /Users/danielnguyen/Castle
./Scripts/package-app.sh
open /Users/danielnguyen/Castle/dist/Castle.app
```

## Test

```bash
cd /Users/danielnguyen/Castle
swift test
```

## Drafting Controls (Current)

- `Select`: inspection mode
- `LINE`: click start, click end
- `CIRCLE`: click center, click radius point
- `RECT`: click corner A, click corner B
- `PLINE`: click vertices to chain segments, double-click or `Enter` to finish
- Pan: right-drag (or `Option` + left-drag)
- Zoom: `Command` + mouse wheel
- `Esc`: cancel in-progress tool action
- File menu: open/save DXF, publish PDF

## Icon Generation

Castle uses a Drawbridge-style minimal icon workflow:

```bash
cd /Users/danielnguyen/Castle
swift Scripts/generate-icon.swift
```

Generated source icon:

`/Users/danielnguyen/Castle/Assets/AppIcon.iconset/icon_1024x1024.png`

To use a custom icon PNG (for example, from design comps), save it as:

`/Users/danielnguyen/Castle/Assets/AppIcon.source.png`

Then run:

```bash
cd /Users/danielnguyen/Castle
./Scripts/package-app.sh
```

## v0 Product Direction

Castle is a DXF-native CAD desktop app.

The core user loop is:
1. Open a `.dxf` file (or start a new drawing).
2. Draft/edit geometry in Castle.
3. Save updates back into `.dxf`.
4. Publish to `.pdf` for downstream review and markup in Drawbridge.

This keeps Castle focused on drafting and keeps Drawbridge focused on PDF markup.
