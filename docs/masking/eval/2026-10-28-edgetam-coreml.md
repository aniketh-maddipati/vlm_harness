# EdgeTAM → Core ML — attempt 2026-10-28

Tried under `/Volumes/LuminaFactory` with `venv-edgetam` + `coremltools` on
`/Volumes/LuminaFactory/ref/EdgeTAM` (`coreml/export_to_coreml.py` and a traced
image-encoder-only retry).

## Result: blocked

Both conversions fail in coremltools' Torch frontend on an `int` op:

```
TypeError: only 0-dimensional arrays can be converted to Python scalars
```

at `coremltools/converters/mil/frontend/torch/ops.py` `_cast` / `_int` while
converting the image encoder (~954/987 MIL ops). The stock exporter and a
`torch.jit.trace` wrapper that avoids Python shape scalars hit the same error.

Video-memory attention was therefore **not** preserved into an `.mlpackage`;
nothing was wired into `SkimTracker`.

## Lab numbers that still stand (Python EdgeTAM, DAVIS 2017 val)

| path | J&F | fps | vj |
|---|---:|---:|---:|
| edgetam (mask-start) | 0.788 | 8.8 | 0.801 |
| edgetam-apple-click | 0.755 | 9.0 | 0.767 |

Target for ship: ≥0.75 J&F @ ≥15 fps on Core ML. J&F is already clear in Python;
fps and Core ML conversion remain open. Next options: pin an older torch+coremltools
pair known to export SAM2-family encoders, or export via `ct.convert` with a
manually rewritten MIL graph for the failing `int` nodes.
