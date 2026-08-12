#!/usr/bin/env python3
"""Stable derivedDataPath cache for xcodebuild build-for-testing (F04.1).

Keyed by source-tree content hash + tokens.yaml hash. Reuse when unchanged;
rebuild when either input changes.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE_ROOT = ROOT / "artifacts" / "harness" / "build-cache"
MANIFEST_NAME = ".lumina-build-cache.json"

# Inputs that invalidate the pre-merge / UI test build products.
SOURCE_PREFIXES = (
    "Lumina",
    "Lumina.xcodeproj",
    "LuminaLogicTests",
    "LuminaUITests",
    "TestPlans",
    "DesignTokens",
)

sys.path.insert(0, str(ROOT / "Scripts" / "harness" / "codegen"))
from tokens_codegen import DEFAULT_YAML, tokens_hash  # noqa: E402


def compute_source_hash() -> str:
    proc = subprocess.run(
        ["git", "ls-files", "-z", *SOURCE_PREFIXES],
        cwd=str(ROOT),
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError("git ls-files failed — is this a git checkout?")
    paths = [p for p in proc.stdout.split(b"\0") if p]
    digest = hashlib.sha256()
    for rel in sorted(paths):
        digest.update(rel)
        digest.update(b"\0")
        path = ROOT / rel.decode("utf-8", errors="replace")
        if path.is_file():
            digest.update(path.read_bytes())
        digest.update(b"\n")
    return digest.hexdigest()


def compute_tokens_hash() -> str:
    yaml_path = DEFAULT_YAML
    if not yaml_path.is_file():
        raise RuntimeError(f"missing {yaml_path.relative_to(ROOT)}")
    return tokens_hash(yaml_path.read_bytes())


def cache_key(source: str | None = None, tokens: str | None = None) -> str:
    src = source or compute_source_hash()
    tok = tokens or compute_tokens_hash()
    return f"{src[:12]}-{tok[:12]}"


def derived_data_path(source: str | None = None, tokens: str | None = None) -> Path:
    return CACHE_ROOT / cache_key(source, tokens)


def manifest_path(derived: Path) -> Path:
    return derived / MANIFEST_NAME


def read_manifest(derived: Path) -> dict | None:
    path = manifest_path(derived)
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def write_manifest(derived: Path, source: str, tokens: str) -> None:
    derived.mkdir(parents=True, exist_ok=True)
    payload = {
        "schemaVersion": 1,
        "source_hash": source,
        "tokens_hash": tokens,
        "cache_key": cache_key(source, tokens),
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "build_for_testing": True,
    }
    manifest_path(derived).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def has_build_products(derived: Path) -> bool:
    products = derived / "Build" / "Products"
    if not products.is_dir():
        return False
    has_app = any(products.rglob("Lumina.app"))
    has_logic = any(products.rglob("LuminaLogicTests.xctest"))
    has_ui = any(products.rglob("LuminaUITests.xctest"))
    has_xctestrun = any(products.rglob("*.xctestrun"))
    return has_app and has_logic and has_ui and has_xctestrun


def cache_hit(derived: Path | None = None) -> bool:
    source = compute_source_hash()
    tokens = compute_tokens_hash()
    path = derived or derived_data_path(source, tokens)
    manifest = read_manifest(path)
    if not manifest:
        return False
    if manifest.get("source_hash") != source or manifest.get("tokens_hash") != tokens:
        return False
    if not manifest.get("build_for_testing"):
        return False
    return has_build_products(path)


def run_build_for_testing(derived: Path, configuration: str = "Debug") -> None:
    derived.mkdir(parents=True, exist_ok=True)
    common = [
        "xcodebuild",
        "-project",
        str(ROOT / "Lumina.xcodeproj"),
        "-scheme",
        "Lumina",
        "-configuration",
        configuration,
        "-derivedDataPath",
        str(derived),
        "-destination",
        "platform=macOS",
    ]
    for target in ("build", "build-for-testing"):
        proc = subprocess.run(common + [target], cwd=str(ROOT))
        if proc.returncode != 0:
            raise RuntimeError(f"xcodebuild {target} failed (exit {proc.returncode})")


def ensure_build_for_testing(configuration: str = "Debug") -> tuple[str, Path, bool]:
    """Return (cache_key, derived_path, was_hit). Rebuild on miss."""
    source = compute_source_hash()
    tokens = compute_tokens_hash()
    key = cache_key(source, tokens)
    derived = derived_data_path(source, tokens)
    if cache_hit(derived):
        return key, derived, True
    run_build_for_testing(derived, configuration=configuration)
    if not has_build_products(derived):
        raise RuntimeError(
            f"build-for-testing finished but products missing under {derived.relative_to(ROOT)}"
        )
    write_manifest(derived, source, tokens)
    return key, derived, False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived-data-path", action="store_true", help="Print stable derivedDataPath")
    parser.add_argument("--cache-key", action="store_true", help="Print source+tokens cache key")
    parser.add_argument("--cache-hit", action="store_true", help="Exit 0 when cache valid, 1 on miss")
    parser.add_argument(
        "--ensure-build-for-testing",
        action="store_true",
        help="Reuse cache or run xcodebuild build + build-for-testing (macOS only)",
    )
    parser.add_argument("--configuration", default="Debug")
    args = parser.parse_args(argv)

    if args.derived_data_path:
        print(derived_data_path())
        return 0
    if args.cache_key:
        print(cache_key())
        return 0
    if args.cache_hit:
        if cache_hit():
            print("build_cache: hit")
            return 0
        print("build_cache: miss", file=sys.stderr)
        return 1
    if args.ensure_build_for_testing:
        key, derived, hit = ensure_build_for_testing(configuration=args.configuration)
        rel = derived.relative_to(ROOT)
        if hit:
            print(f"build_cache: hit key={key} derivedDataPath={rel}")
        else:
            print(f"build_cache: rebuilt key={key} derivedDataPath={rel}")
        return 0

    parser.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
