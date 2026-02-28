Castle is a native macOS 2D drafting app focused on DXF workflows for architecture offices, with fast navigation, precise drawing tools, DXF save/open, DWG import via conversion, and PDF publishing.

## Requirements

- Apple Silicon Mac (M1 or newer)
- macOS 13.0 or newer

## Download

Get the latest release here:

https://github.com/dansc89/Castle/releases/latest

Download the `.dmg`, open it, then drag **Castle.app** into **Applications**.

## Quick Start

1. Open Castle.
2. Open a `.dxf` file, or use **File -> Import DWG (Convert to DXF)...**.
3. Draft with the tools (`LINE`, `PLINE`, `RECT`, `CIRCLE`) and save as DXF.
4. Export to PDF when needed.

## DWG Conversion

Castle's DWG import relies on the GPL `dwg2dxf` converter from [`libdxfrw`](https://github.com/codelibs/libdxfrw). To make sure the converter is always available:

1. Run `./Scripts/setup-dwg2dxf.sh` (requires `git` and `cmake`) to clone/build `libdxfrw` and install the `dwg2dxf` binary under `~/Library/Application Support/Castle/Converters/dwg2dxf/dwg2dxf` (or another path you choose via `CASTLE_DWG_CONVERTER_ROOT`).
2. Castle looks for a converter in this order: `CASTLE_DWG2DXF_PATH`, the default install location, and finally whatever `dwg2dxf` is on `PATH`. If you prefer to ship a custom build, set `CASTLE_DWG2DXF_PATH` to that executable before launching Castle.

If you prefer the ODA File Converter, Castle will still fall back to `/Applications/ODA File Converter.app`/`ODAFileConverter.app` if those bundles are installed.

## Support

If you hit an issue, open a GitHub issue with:
- the file you opened
- what action you took
- what happened vs expected behavior

## Developer Docs

Developer/build/release docs are in `DEVELOPMENT.md`.
