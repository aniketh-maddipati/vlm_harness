#!/usr/bin/env python3
"""Golden service — propose → approve re-goldening (never auto-bless).

Goldens are keyed by tokens-hash so a token change invalidates exactly the
goldens that depend on chrome metrics.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
STORE = ROOT / "artifacts" / "harness" / "goldens"
TOKENS_HASH_PATH = ROOT / "artifacts" / "harness" / "tokens.hash"


def tokens_hash() -> str:
    if TOKENS_HASH_PATH.is_file():
        data = json.loads(TOKENS_HASH_PATH.read_text(encoding="utf-8"))
        return str(data["tokens_hash"])
    raw = (ROOT / "design" / "tokens.yaml").read_bytes()
    return hashlib.sha256(raw).hexdigest()


@dataclass
class GoldenRef:
    name: str
    tokens_hash: str

    @property
    def dir(self) -> Path:
        return STORE / self.tokens_hash / self.name

    @property
    def approved_path(self) -> Path:
        return self.dir / "approved.json"

    @property
    def proposed_path(self) -> Path:
        return self.dir / "proposed.json"


def propose(name: str, payload: dict, *, digest: str | None = None) -> Path:
    ref = GoldenRef(name=name, tokens_hash=digest or tokens_hash())
    ref.dir.mkdir(parents=True, exist_ok=True)
    body = {
        "name": name,
        "tokens_hash": ref.tokens_hash,
        "proposed_at": datetime.now(timezone.utc).isoformat(),
        "status": "proposed",
        "payload": payload,
    }
    ref.proposed_path.write_text(json.dumps(body, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return ref.proposed_path


def approve(name: str, *, digest: str | None = None) -> Path:
    ref = GoldenRef(name=name, tokens_hash=digest or tokens_hash())
    if not ref.proposed_path.is_file():
        raise FileNotFoundError(f"no proposal for {name} @ {ref.tokens_hash}")
    proposed = json.loads(ref.proposed_path.read_text(encoding="utf-8"))
    proposed["status"] = "approved"
    proposed["approved_at"] = datetime.now(timezone.utc).isoformat()
    ref.approved_path.write_text(json.dumps(proposed, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return ref.approved_path


def compare(name: str, payload: dict, *, digest: str | None = None) -> dict:
    ref = GoldenRef(name=name, tokens_hash=digest or tokens_hash())
    if not ref.approved_path.is_file():
        return {"ok": False, "reason": "missing_approved", "ref": str(ref.approved_path)}
    approved = json.loads(ref.approved_path.read_text(encoding="utf-8"))
    if approved.get("tokens_hash") != ref.tokens_hash:
        return {"ok": False, "reason": "tokens_hash_mismatch"}
    same = approved.get("payload") == payload
    return {"ok": same, "reason": "match" if same else "diff", "ref": str(ref.approved_path)}


def invalidate_for_tokens_change(old_hash: str, new_hash: str) -> list[str]:
    """Return golden names that exist under old_hash and are absent under new_hash."""
    old_dir = STORE / old_hash
    if not old_dir.is_dir():
        return []
    names = []
    for child in old_dir.iterdir():
        if child.is_dir():
            names.append(child.name)
            dest = STORE / new_hash / child.name
            dest.mkdir(parents=True, exist_ok=True)
            # Copy proposals as stale markers — never auto-approve.
            marker = dest / "STALE_TOKENS.md"
            marker.write_text(
                f"Invalidated by tokens-hash change {old_hash[:12]}… → {new_hash[:12]}…\n"
                "Re-propose and approve deliberately.\n",
                encoding="utf-8",
            )
    return names


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("propose")
    p.add_argument("name")
    p.add_argument("--file", type=Path, required=True)
    a = sub.add_parser("approve")
    a.add_argument("name")
    c = sub.add_parser("compare")
    c.add_argument("name")
    c.add_argument("--file", type=Path, required=True)
    sub.add_parser("hash")
    args = parser.parse_args(argv)
    if args.cmd == "hash":
        print(tokens_hash())
        return 0
    if args.cmd == "propose":
        payload = json.loads(args.file.read_text(encoding="utf-8"))
        path = propose(args.name, payload)
        print(path)
        return 0
    if args.cmd == "approve":
        path = approve(args.name)
        print(path)
        return 0
    if args.cmd == "compare":
        payload = json.loads(args.file.read_text(encoding="utf-8"))
        result = compare(args.name, payload)
        print(json.dumps(result, indent=2))
        return 0 if result.get("ok") else 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
