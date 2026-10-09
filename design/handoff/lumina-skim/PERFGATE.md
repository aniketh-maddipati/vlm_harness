# Skim perf gate: speed numbers that can only go up (branch video/skim-perfgate)

Goal: every change is measured the same way, and a regression fails the build. Owner of the benchmark harness and
budgets (Tests/web/skim-perf.*, a CI job, a Mac-side runner), not of the speedups themselves (ingest, canvas,
native own those). Merge video/skim-mvp regularly; never edit the page except a debug hook if one is missing.

## Measure (headless Chromium in CI with VP9/H.264-free fixtures; Safari/WebKit on the Mac by a script the user runs)
- Open → list on screen; first look (every cover); usable flags; all frames — from the page's clock.
- Interaction: key-to-paint for ←→ in Clips at 160/600/1,500/4,000 clips (test loads); slider drag 1→N frame times
  (median, p95, worst); drag-select frame times; zoom; dock updates (when the canvas lands).
- Main-thread long tasks (> 50 ms) during reading; memory (JS heap, decoded thumbnails, frames) at 400 and 4,000.
- Repaints per second while reading.
Budgets to start (to confirm with the user; tighten as work lands): Clips key p95 ≤ 50 ms at 1,500; slider drag
p95 ≤ 20 ms at 500; no long task > 100 ms while reading; heap ≤ 150 MB at 1,500; decoded thumbnails within budget.
## Deliver
A runner that prints a table and writes results JSON; budgets in one file; a CI step (like Tests/web/skim-export);
a README for the Mac/Safari run against /Volumes/Untitled (read only) and T7/friend_test_log; a baseline committed
from today's video/skim-mvp so later work is compared against it.
