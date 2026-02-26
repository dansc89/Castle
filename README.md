# Castle (working title)

Castle is a DXF-native CAD app in the Drawbridge cinematic universe.

Where Drawbridge is the PDF markup editor, Castle is the drafting tool:
- open DXF
- edit geometry
- save DXF
- publish drawings to PDF when done

## v0 Scope

- Open existing `.dxf` files
- Import `.dwg` via guarded conversion to `.dxf` with validation report output
- Create and edit basic entities (`LINE`, `CIRCLE`)
- Save back to `.dxf`
- Export drawing output to `.pdf`
- Keep the architecture local-first and offline-capable

## Requirements

- Apple Silicon Mac (M1/M2/M3/M4)
- macOS 13.0 or newer

## Run

```bash
cd /Users/danielnguyen/Castle
swift run
```

## Name

`Castle` is a working name. The repo/package can be renamed once product naming is finalized.
