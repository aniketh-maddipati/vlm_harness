#!/usr/bin/env python3
"""Generate Swift token constants from design/tokens.yaml (contract → tokens → code).

Authority: design/contract-v6.md → design/tokens.yaml → generated Swift.
Do not hand-edit the output file; re-run this script.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError as exc:  # pragma: no cover
    raise SystemExit("PyYAML required: pip install pyyaml") from exc

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_YAML = ROOT / "design" / "tokens.yaml"
DEFAULT_OUT = ROOT / "DesignTokens" / "HiFiTokens.generated.swift"
DEFAULT_HASH = ROOT / "artifacts" / "harness" / "tokens.hash"


META_KEYS = {"version", "contract", "codegen"}


def snake_to_camel(name: str) -> str:
    parts = name.split("_")
    if not parts:
        return name
    return parts[0] + "".join(p[:1].upper() + p[1:] if p else "" for p in parts[1:])


# Swift reserved / ambiguous type names that cannot be nested enum identifiers.
SECTION_ENUM_ALIASES = {
    "type": "Typography",
}


def section_to_enum(name: str) -> str:
    if name in SECTION_ENUM_ALIASES:
        return SECTION_ENUM_ALIASES[name]
    return "".join(p[:1].upper() + p[1:] for p in name.split("_") if p)


def tokens_hash(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def load_tokens(path: Path) -> tuple[dict, bytes]:
    raw = path.read_bytes()
    data = yaml.safe_load(raw)
    if not isinstance(data, dict):
        raise SystemExit(f"tokens.yaml root must be a mapping: {path}")
    return data, raw


def resolve_ref(data: dict, ref: str):
    cur: object = data
    for part in ref.split("."):
        if not isinstance(cur, dict) or part not in cur:
            raise KeyError(ref)
        cur = cur[part]
    return cur


def leaf_entries(section: dict, data: dict) -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    for key, node in section.items():
        if not isinstance(node, dict):
            continue
        if "ref" in node:
            target = resolve_ref(data, node["ref"])
            if isinstance(target, dict) and ("value" in target or "ref" in target):
                merged = dict(target)
                merged.setdefault("cite", node.get("cite"))
                out.append((key, merged))
            continue
        if "value" in node:
            out.append((key, node))
    return out


def swift_literal(value, typ: str, unit: str | None) -> str:
    if typ == "color":
        return f'"{value}"'
    if typ == "bool":
        return "true" if value else "false"
    if typ == "string":
        escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    if typ == "opacity":
        return _float_lit(value)
    if typ in {"pt", "px"}:
        return _float_lit(value)
    if typ == "ms":
        # Expose milliseconds as TimeInterval seconds for animation consumers.
        return _float_lit(float(value) / 1000.0)
    if typ == "animation":
        return _float_lit(value)
    if typ == "enum":
        if isinstance(value, list):
            items = ", ".join(swift_literal(v, _infer_list_type(value), None) for v in value)
            return f"[{items}]"
        if isinstance(value, bool):
            return "true" if value else "false"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return _num_lit(value)
        if value is None:
            return "nil"
        escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    # fallback
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return _num_lit(value)
    if value is None:
        return "nil"
    escaped = str(value).replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _infer_list_type(values: list) -> str:
    if all(isinstance(v, str) for v in values):
        return "string"
    if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in values):
        return "pt"
    return "enum"


def _float_lit(value) -> str:
    f = float(value)
    if f == int(f) and abs(f) < 1e9:
        return f"{int(f)}.0"
    text = f"{f:.6f}".rstrip("0").rstrip(".")
    if "." not in text:
        text += ".0"
    return text


def _num_lit(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    return _float_lit(value)


def swift_type(value, typ: str) -> str:
    if typ == "color":
        return "String"
    if typ == "bool":
        return "Bool"
    if typ == "string":
        return "String"
    if typ == "opacity":
        return "Double"
    if typ in {"pt", "px", "animation"}:
        return "CGFloat"
    if typ == "ms":
        return "TimeInterval"
    if typ == "enum":
        if isinstance(value, list):
            if not value:
                return "[String]"
            if all(isinstance(v, str) for v in value):
                return "[String]"
            if all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value):
                return "[CGFloat]"
            return "[Any]"
        if isinstance(value, bool):
            return "Bool"
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            return "CGFloat" if isinstance(value, float) else "Int"
        if value is None:
            return "String?"
        return "String"
    return "String"


def cite_comment(node: dict) -> str:
    cite = node.get("cite") or []
    if isinstance(cite, list):
        body = ", ".join(str(c) for c in cite)
    else:
        body = str(cite)
    notes = node.get("notes")
    if notes:
        return f" // cite: {body} — {notes}"
    return f" // cite: {body}" if body else ""


def render_section(enum_name: str, section: dict, data: dict) -> str:
    lines = [f"    enum {enum_name} {{"]
    for key, node in leaf_entries(section, data):
        typ = str(node.get("type") or "enum")
        value = node.get("value")
        unit = node.get("unit")
        name = snake_to_camel(key)
        # Avoid colliding with the assertDistinctSelectionAndHalo() helper below.
        if enum_name == "Ring" and key == "assert_distinct_selection_and_halo":
            name = "distinctSelectionAndHaloRequired"
        if value is None and typ == "enum":
            lines.append(f"        static let {name}: String? = nil{cite_comment(node)}")
            continue
        st = swift_type(value, typ)
        lit = swift_literal(value, typ, unit)
        lines.append(f"        static let {name}: {st} = {lit}{cite_comment(node)}")
        if typ == "ms":
            # Also expose raw milliseconds for signpost / ledger asserts.
            lines.append(
                f"        static let {name}Ms: Int = {int(value)}{cite_comment(node)}"
            )
    if enum_name == "Ring":
        lines.extend(
            [
                "",
                "        // Color conveniences for UI call sites (hex strings above are source of truth).",
                "        static let selection = SwiftUI.Color(hifiHex: selectionColor)",
                "        static let halo = SwiftUI.Color(hifiHex: haloColor)",
                "        static let fallbackA = SwiftUI.Color(hifiHex: fallbackAHaloColor)",
                "",
                "        static func assertDistinctSelectionAndHalo() {",
                "            assert(distinctSelectionAndHaloRequired, \"selection/halo must stay distinct\")",
                "            assert(selection != halo, \"selection ring and table halo must not share the same color\")",
                "        }",
            ]
        )
    lines.append("    }")
    return "\n".join(lines)


def render_compat_aliases() -> str:
    """Call-site compatibility nested types used by existing UI (values from yaml)."""
    return """
    // MARK: - Compatibility aliases (yaml-backed; do not hand-literal)

    enum SwimLane {
        /// Socket only — lane plates shelved (D64 / A6).
        static let fillOpacity: Double = Color.swimlaneFillOpacity
        static let parchment = SwiftUI.Color(hifiHex: Color.parchment)
        static var fill: SwiftUI.Color { parchment.opacity(fillOpacity) }
        /// Pre-yaml chrome inset retained until CP1 layout seal owns a token.
        static let headerInset = SwiftUI.Color(red: 242 / 255, green: 239 / 255, blue: 233 / 255, opacity: 0.22)
    }

    enum Histogram {
        static let width: CGFloat = Layout.histogramWidth
        static let height: CGFloat = Layout.histogramHeight
    }

    enum Crop {
        static let handleSize: CGFloat = Hit.cropHandle
        static let minimumHit: CGFloat = Hit.cropMinimum
    }

    enum DockedChipDrag {
        static let grabDuration: TimeInterval = Motion.dockedChipGrab
        static let carryDuration: TimeInterval = Motion.dockedChipCarry
        static let placeDuration: TimeInterval = Motion.dockedChipPlace
    }
"""


def generate_swift(data: dict, digest: str) -> str:
    version = data.get("version", "unknown")
    contract = data.get("contract", "design/contract-v6.md")
    sections = []
    for key, section in data.items():
        if key in META_KEYS:
            continue
        if not isinstance(section, dict):
            continue
        sections.append(render_section(section_to_enum(key), section, data))

    body = "\n\n".join(sections)
    return f"""// HiFiTokens.generated.swift
// GENERATED from design/tokens.yaml — do not edit by hand.
// Re-run: python3 Scripts/harness/codegen/tokens_codegen.py
// tokens-hash: {digest}
// version: {version}
// contract: {contract}

import CoreGraphics
import Foundation
import SwiftUI

enum HiFiTokens {{
{body}
{render_compat_aliases()}
}}

private extension SwiftUI.Color {{
    init(hifiHex: String) {{
        let cleaned = hifiHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }}
}}
"""


def write_outputs(data: dict, raw: bytes, out_path: Path, hash_path: Path) -> str:
    digest = tokens_hash(raw)
    swift = generate_swift(data, digest)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(swift, encoding="utf-8")
    hash_path.parent.mkdir(parents=True, exist_ok=True)
    hash_path.write_text(
        json.dumps({"tokens_hash": digest, "source": "design/tokens.yaml"}, indent=2) + "\n",
        encoding="utf-8",
    )
    return digest


def check_fresh(data: dict, raw: bytes, out_path: Path) -> int:
    digest = tokens_hash(raw)
    expected = generate_swift(data, digest)
    if not out_path.is_file():
        print(f"FAIL: missing generated tokens: {out_path}", file=sys.stderr)
        return 1
    actual = out_path.read_text(encoding="utf-8")
    if actual != expected:
        print(f"FAIL: {out_path} is stale vs design/tokens.yaml", file=sys.stderr)
        print("  re-run: python3 Scripts/harness/codegen/tokens_codegen.py", file=sys.stderr)
        return 1
    # Hash stamp inside file
    if f"tokens-hash: {digest}" not in actual:
        print("FAIL: generated file missing tokens-hash stamp", file=sys.stderr)
        return 1
    print(f"tokens_codegen.py: OK (hash={digest[:12]}…)")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--yaml", type=Path, default=DEFAULT_YAML)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--hash-out", type=Path, default=DEFAULT_HASH)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Verify generated Swift matches tokens.yaml (no write)",
    )
    args = parser.parse_args(argv)
    data, raw = load_tokens(args.yaml)
    if args.check:
        return check_fresh(data, raw, args.out)
    digest = write_outputs(data, raw, args.out, args.hash_out)
    print(f"wrote {args.out} (tokens-hash={digest[:12]}…)")
    print(f"wrote {args.hash_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
