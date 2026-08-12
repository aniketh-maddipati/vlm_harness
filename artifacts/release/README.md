# Release artifacts (F11.5 / D51 / R-I.2)

Rollback = copy `shipped/previous/Lumina.app` — no rebuild.

```bash
python3 Scripts/harness/release/retain_shipped_artifact.py promote --app build/Release/Lumina.app
```

`shipped/current/` and `shipped/previous/` are gitignored (app binaries). Manifest JSON lives beside each copy on disk.
