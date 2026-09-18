# RAW backend benchmark boundary

Production uses `AppleRawDecodeBackend` (`CIRAWFilter`) only. The
`--raw-backend-benchmark` runner measures reduced and full-resolution Apple
decode against `raw-correctness-v1`; LibRaw and RawSpeed remain explicit,
unlinked inventory entries.

An alternate backend is not a slider optimization. Interactive look ticks use
the materialized RAW-stage texture and must not demosaic. A candidate must
improve measured cold/open, neighbor, 1:1, or export misses.

## Admission gate

Before linking a candidate:

1. Legal review records the exact version and license. LibRaw offers LGPL 2.1
   or CDDL 1.0; bundled components must be audited independently. RawSpeed is
   LGPL 2.1-or-later.
2. The version supports every claimed container/body. RawSpeed is not treated
   as a universal decoder; in particular, CR3 support must be verified against
   the selected release rather than inferred from an open patch.
3. The non-shipping adapter reports reduced/full decode latency, peak memory,
   cancellation, orientation, camera crop, black/white levels, WB matrices,
   highlight behavior, lens correction, and output deltas against Apple.
4. The candidate works inside the sandbox and does not fork display/export
   color policy.
5. A separate review explicitly enables it. The production registry must
   continue to contain only Apple until that change.

The benchmark report is evidence, not automatic backend selection.
