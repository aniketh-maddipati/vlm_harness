#!/usr/bin/env bash
# Stops everything test-related on this Mac. Safe to run at any time, from any checkout.
#
#   bash Scripts/stop_tests.sh             stop: guarded runs, probes, UI test runners and the scripts
#                                          that start them (parents first, so nothing respawns), test
#                                          builds of the app, the probe's disk images, listening test
#                                          servers, the tests' temp folders. Exit 1 if something is left.
#   bash Scripts/stop_tests.sh --dry-run   only list what it would stop (also: Scripts/test_guard.py status)
#
# Never touched: /Applications/Lumina.app, real volumes (an image is chosen by where its file is,
# never by its mount point), ~/LuminaEvidence's contents, other Claude sessions (they are listed).
exec /usr/bin/env python3 "$(cd "$(dirname "$0")" && pwd)/test_guard.py" stop "$@"
