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

## DWG Converter Setup

Castle imports DWG files by calling the GPL `dwg2dxf` converter from `libdxfrw`. Before using the feature:

1. Ensure `git` and `cmake` are installed.
2. Run `./Scripts/setup-dwg2dxf.sh`; it will clone/update `libdxfrw`, build the `dwg2dxf` target, and install the binary under `~/Library/Application Support/Castle/Converters/dwg2dxf/dwg2dxf` (or `CASTLE_DWG_CONVERTER_ROOT` if that env var is set).
3. Optionally override the binary path with `CASTLE_DWG2DXF_PATH` when launching Castle.

The app checks `CASTLE_DWG2DXF_PATH`, then the default install directory, and finally whatever `dwg2dxf` exists on `PATH`. If those all fail Castle falls back to the ODA File Converter if it is installed in `/Applications`.

The release build bundles the converter inside `Contents/Resources/Converters/dwg2dxf`, so the packaged app already has everything needed for DWG import. Use `setup-dwg2dxf.sh` only when you need to rebuild or swap the binary for development/testing.

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
