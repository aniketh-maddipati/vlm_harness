# Develop Lab delivery notes (Linux cloud agent)

## Branch state at implementation

| Item | Value |
|---|---|
| Base | `cursor/ethereal-ui` @ `9015e04` |
| Feature branch | `cursor/raw-develop-engine-f537` |
| Working tree before edits | Clean (no dirty user files to preserve) |
| Cloud host | Ubuntu — **cannot** run `xcodebuild`, CIRAWFilter, or live ARW |

## What was built

Phase 1 isolated Develop Lab + deterministic recipe/render/batch architecture. Workbench integration deferred until live-RAW gates pass on a Mac.

## Verification on this host

| Check | Result |
|---|---|
| `python3 Scripts/develop_engine_test.py` | PASS (12 checks) |
| `python3 Scripts/develop_fidelity_test.py` | blocked (no PNG pair / no Pillow) |
| `bash -n Scripts/regression.sh` | PASS |
| `xcodebuild` | Not available on Linux |
| Live RAW / Develop Lab GUI | Blocked — no ARW fixtures on VM |
| Performance measurements | Not collected — requires macOS + representative hardware |

## Next smallest validation step (Mac)

1. `xcodebuild -project Lumina.xcodeproj -scheme Lumina -configuration Debug build`
2. Launch with `--develop-lab --develop-raw-dir /path/to/raw/folder`
3. Scrub Exposure/WB; confirm fidelity chip moves Interactive → Settling → Full Preview
4. Before/After and 1:1; stage/commit batch across 3 ARWs; confirm local override isolation
5. Capture screenshots into `artifacts/develop-lab/`; run fidelity script on preview vs downsampled export
6. Only then wire Workbench Edit mode to `DevelopRenderScheduler`
