#!/usr/bin/env python3
"""Write LuminaBuildManifest.json for embedding in Lumina.app (F11.4).

Invoked from the Xcode Run Script build phase and by release harness scripts.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_OUT = ROOT / "Lumina" / "Resources" / "LuminaBuildManifest.json"
TOKENS_HASH = ROOT / "artifacts" / "harness" / "tokens.hash"
TOKENS_YAML = ROOT / "design" / "tokens.yaml"
FIXTURE_YAML = ROOT / "design" / "fixture-manifest.yaml"


def git_sha() -> str:
    proc = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        return "unknown"
    return proc.stdout.strip()


def tokens_hash() -> str:
    if TOKENS_HASH.is_file():
        data = json.loads(TOKENS_HASH.read_text(encoding="utf-8"))
        return str(data["tokens_hash"])
    import hashlib

    raw = TOKENS_YAML.read_bytes()
    return hashlib.sha256(raw).hexdigest()


def _yaml_scalar(path: Path, key: str) -> str:
    if not path.is_file():
        return "unknown"
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(f"{key}:"):
            val = line.split(":", 1)[1].strip()
            return val.strip('"').strip("'")
    return "unknown"


def contract_version() -> str:
    return _yaml_scalar(TOKENS_YAML, "version")


def fixture_manifest_version() -> str:
    return _yaml_scalar(FIXTURE_YAML, "version")


def marketing_version_from_env() -> str:
    for key in ("MARKETING_VERSION", "LUMINA_MARKETING_VERSION"):
        val = __import__("os").environ.get(key)
        if val:
            return val
    return "0.1.0"


def bundle_version_from_env() -> str:
    val = __import__("os").environ.get("CURRENT_PROJECT_VERSION")
    return val or "1"


def configuration_from_env() -> str:
    return __import__("os").environ.get("CONFIGURATION", "Release")


def beta_diagnostics_from_socket() -> dict | None:
    """Mirror BetaDiagnosticsSocket.activeKind in Lumina/Core/BetaDiagnosticsSocket.swift."""
    socket = ROOT / "Lumina" / "Core" / "BetaDiagnosticsSocket.swift"
    if not socket.is_file():
        return None
    text = socket.read_text(encoding="utf-8")
    if "activeKind: String? = nil" in text:
        return None
    # Non-nil socket — F11.6 FAIL; mirror kind for manifest embed diagnostics only.
    kind = "unspecified"
    if 'activeKind: String? = "' in text:
        import re

        m = re.search(r'activeKind:\s*String\?\s*=\s*"([^"]+)"', text)
        if m:
            kind = m.group(1)
    return {
        "kind": kind,
        "path": "Lumina/Core/BetaDiagnosticsSocket.swift",
        "expiresAtMarketingVersion": "1.0",
        "cite": ["D45", "A13"],
    }


def build_manifest() -> dict:
    payload = {
        "schemaVersion": 1,
        "gitSha": git_sha(),
        "tokensHash": tokens_hash(),
        "fixtureManifestVersion": fixture_manifest_version(),
        "contractVersion": contract_version(),
        "buildDate": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "marketingVersion": marketing_version_from_env(),
        "bundleVersion": bundle_version_from_env(),
        "configuration": configuration_from_env(),
        "betaDiagnostics": beta_diagnostics_from_socket(),
    }
    return payload


def write_manifest(out: Path) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = build_manifest()
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--print", action="store_true", dest="print_json")
    args = parser.parse_args(argv)
    path = write_manifest(args.out)
    if args.print_json:
        print(path.read_text(encoding="utf-8"), end="")
    else:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
