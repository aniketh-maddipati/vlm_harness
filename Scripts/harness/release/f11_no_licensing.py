#!/usr/bin/env python3
"""F11.7 — wave builds must not ship licensing / activation / expiry machinery (D52 / A8).

Beta licensing token is `none`. This gate greps Lumina/ for forbidden patterns with
an allowlist for AppKit activation policy and unrelated 'install' helpers.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LUMINA = ROOT / "Lumina"
TOKENS = ROOT / "design" / "tokens.yaml"

# Case-insensitive product-code patterns (not user-visible copy alone).
PATTERNS: list[tuple[str, re.Pattern[str]]] = [
    ("license_key", re.compile(r"\blicense[_ ]?key\b", re.I)),
    ("activation_code", re.compile(r"\bactivation[_ ]?(code|key|server)\b", re.I)),
    ("trial_expir", re.compile(r"\btrial[_ ]?expir", re.I)),
    ("subscription", re.compile(r"\b(subscription|subscribe)\b", re.I)),
    ("receipt_validation", re.compile(r"\breceipt[_ ]?valid", re.I)),
    ("storekit", re.compile(r"\bStoreKit\b")),
    ("licensing_service", re.compile(r"\bLicensing(Service|Manager|Gate)\b")),
]

ALLOWLIST_LINE = (
    r"NSApp\.setActivationPolicy|installMemoryPressureHandler|installKeys|"
    r"BetaDiagnosticsSocket|beta_licensing|grammar\.beta_licensing|"
    r"//|setAccessibility|activator|Activation state|noteConfirm|"
    r"DevelopLab|RawHarness|WorkbenchCapture"
)


def beta_licensing_none() -> bool:
    if not TOKENS.is_file():
        return False
    text = TOKENS.read_text(encoding="utf-8")
    return "beta_licensing:" in text and "value: none" in text.split("beta_licensing:")[1][:120]


def scan_sources() -> list[str]:
    hits: list[str] = []
    allow = re.compile(ALLOWLIST_LINE, re.I)
    for path in sorted(LUMINA.rglob("*.swift")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if allow.search(line):
                continue
            for label, pattern in PATTERNS:
                if pattern.search(line):
                    rel = path.relative_to(ROOT)
                    hits.append(f"{rel}:{lineno}: [{label}] {line.strip()}")
    return hits


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    args = parser.parse_args(argv)

    print("=== F11.7 no licensing (D52 / A8) ===")
    if not beta_licensing_none():
        print("FAIL: design/tokens.yaml grammar.beta_licensing is not `none`", file=sys.stderr)
        return 1
    print("[PASS] tokens.yaml grammar.beta_licensing = none")

    hits = scan_sources()
    if hits:
        print("\nForbidden licensing / activation patterns:", file=sys.stderr)
        for hit in hits:
            print(f"  {hit}", file=sys.stderr)
        print("\nF11.7: FAIL")
        return 1

    print("[PASS] no licensing / activation / expiry code paths in Lumina/")
    print("\nF11.7: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
