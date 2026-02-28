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

Castle ships with the GPL `dwg2dxf` converter (from [`libdxfrw`](https://github.com/codelibs/libdxfrw)) embedded inside the app at `Contents/Resources/Converters/dwg2dxf/dwg2dxf`, so DWG → DXF conversion works out of the box in the release build.

For development we still provide `./Scripts/setup-dwg2dxf.sh` (requires `git` and `cmake`) so you can rebuild the converter yourself, refresh the binary under `~/Library/Application Support/Castle/Converters/dwg2dxf`, or override the path via `CASTLE_DWG2DXF_PATH`/`CASTLE_DWG_CONVERTER_ROOT`.

Castle will check (in order) `CASTLE_DWG2DXF_PATH`, the embedded resource, the Application Support install location, and finally any `dwg2dxf` on `PATH` before falling back to the ODA File Converter if it is installed in `/Applications`.

## Support

If you hit an issue, open a GitHub issue with:
- the file you opened
- what action you took
- what happened vs expected behavior

## Developer Docs

Developer/build/release docs are in `DEVELOPMENT.md`.
