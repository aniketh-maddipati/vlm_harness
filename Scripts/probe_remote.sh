#!/usr/bin/env bash
# Run a probe suite on another Mac over ssh (the M1 8 GB the roadmap's second targets are for):
# rsync this checkout there (no build products, no evidence), run Scripts/probe.sh <suite> with
# the M1 gates, and pull the evidence back to ~/LuminaEvidence/probe-remote/<stamp>.
#
#   LUMINA_REMOTE=user@m1.local bash Scripts/probe_remote.sh edit
#   LUMINA_REMOTE=user@m1.local LUMINA_REMOTE_EDIT_DIR=/Users/user/Pictures/shoot-3000 bash Scripts/probe_remote.sh raw9
#
#   LUMINA_REMOTE           ssh target (required)
#   LUMINA_REMOTE_DIR       checkout on the remote (default ~/LuminaRemote/vlm_harness)
#   LUMINA_REMOTE_EDIT_DIR  folder of ARWs on the remote for edit / raw9 (default: the suite's own fallback)
#   LUMINA_REMOTE_P95       the drag latency gate there (default 33 ms: the M1 8 GB target)
#   LUMINA_REMOTE_ENV       extra "K=V K=V" for the remote run (e.g. LUMINA_FIXTURE_ROOT=…)
set -euo pipefail
suite="${1:-edit}"; shift || true
remote="${LUMINA_REMOTE:-}"; [[ -n $remote ]] || { echo "set LUMINA_REMOTE=user@host" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rdir="${LUMINA_REMOTE_DIR:-~/LuminaRemote/vlm_harness}"
stamp="$(date +%Y%m%d-%H%M%S)"
local_out="$HOME/LuminaEvidence/probe-remote/$stamp"
mkdir -p "$local_out"

echo "→ syncing $ROOT to $remote:$rdir"
ssh "$remote" "mkdir -p $rdir"
rsync -az --delete --exclude .git --exclude DD --exclude '.build' --exclude 'artifacts' --exclude 'Tools/parity/report' "$ROOT/" "$remote:$rdir/"

envs="LUMINA_EDIT_P95=${LUMINA_REMOTE_P95:-33} LUMINA_PROBE_OUT=$rdir/.evidence/$stamp ${LUMINA_REMOTE_ENV:-}"
[[ -n ${LUMINA_REMOTE_EDIT_DIR:-} ]] && envs="$envs LUMINA_EDIT_DIR=$LUMINA_REMOTE_EDIT_DIR"
echo "→ running probe.sh $suite on $remote ($envs)"
set +e
ssh "$remote" "cd $rdir && env $envs bash Scripts/probe.sh $suite $*"
rc=$?
set -e
echo "→ pulling evidence to $local_out"
rsync -az "$remote:$rdir/.evidence/$stamp/" "$local_out/" || true
ssh "$remote" "sw_vers; sysctl -n machdep.cpu.brand_string hw.memsize" > "$local_out/remote-machine.txt" 2>/dev/null || true
echo "evidence: $local_out (remote exit $rc)"
exit $rc
