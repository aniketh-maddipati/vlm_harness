#!/usr/bin/env python3
"""Subprocess target for journal_kill_fuzz — killed mid partial append."""
from __future__ import annotations

import json
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    journal_path = Path(os.environ["LUMINA_JOURNAL_PATH"])
    committed = int(os.environ.get("LUMINA_JOURNAL_COMMITTED", "8"))
    asset_id = str(uuid.uuid4())

    journal_path.parent.mkdir(parents=True, exist_ok=True)

    with journal_path.open("ab") as handle:
        for seq in range(1, committed + 1):
            record = {
                "id": str(uuid.uuid4()),
                "sequence": seq,
                "recordedAt": datetime.now(timezone.utc).isoformat(),
                "kind": "cull.commit",
                "commandID": str(uuid.uuid4()),
                "assetID": asset_id,
                "cullBefore": "undecided" if seq == 1 else "keep",
                "cullAfter": "keep",
            }
            line = json.dumps(record, sort_keys=True).encode("utf-8") + b"\n"
            handle.write(line)
            handle.flush()
            os.fsync(handle.fileno())

        partial = b'{"id":"' + str(uuid.uuid4()).encode("utf-8") + b'","sequence":'
        handle.write(partial)
        handle.flush()
        # Block until parent SIGKILL — no wall-clock sleep (F04.3).
        sys.stdin.buffer.read(1)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
