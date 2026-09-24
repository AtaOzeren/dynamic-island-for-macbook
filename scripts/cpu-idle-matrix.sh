#!/bin/zsh
# Measures one row (A-E) of the idle CPU cost matrix from the 2026-09-06
# CPU-runaway plan (Task 0.2), using powermetrics' tasks sampler for 60 one-
# second samples, filtered to the running KerNotch process. Appends a result
# line to .omo/evidence/cpu-runaway/idle-matrix-baseline.md and keeps the raw
# powermetrics capture next to it.
#
#   Scripts/cpu-idle-matrix.sh <A|B|C|D|E>
#
# Run it from anywhere; the repo root is derived from this script's location.
# Requires passwordless sudo (run `sudo -v` first) — see the fallback message
# otherwise. The island must be compact and the row's condition must hold for
# the whole minute; the script prints the condition and counts down first.
set -euo pipefail

readonly EVIDENCE_DIR="$(cd "$(dirname "$0")/.." && pwd)/.omo/evidence/cpu-runaway"

readonly row="${1:-}"

case "$row" in
    A) condition="Mouse motionless, single display, no agent" ;;
    B) condition="Mouse moving continuously outside the notch band" ;;
    C) condition="As A, displayTarget = .allDisplays with an external display attached" ;;
    D) condition="As A, one agent working (synthetic session posted to the loopback port)" ;;
    E) condition="As A, expanded island open" ;;
    *)
        echo "usage: Scripts/cpu-idle-matrix.sh <A|B|C|D|E>" >&2
        exit 2
        ;;
esac

pid="$(pgrep -x KerNotch | head -n 1 || true)"
if [[ -z "$pid" ]]; then
    echo "KerNotch is not running — launch the build under test first." >&2
    exit 1
fi
if (( $(pgrep -x KerNotch | wc -l) > 1 )); then
    echo "note: multiple KerNotch processes found; measuring pid $pid" >&2
fi

if ! sudo -n true 2>/dev/null; then
    cat >&2 <<EOF
passwordless sudo is unavailable, so powermetrics cannot run. Either:
  1. run 'sudo -v' to cache your credentials, then re-run this script, or
  2. measure manually: Activity Monitor › KerNotch › Realtime CPU, 30 s
     average, and append the row yourself in $EVIDENCE_DIR/idle-matrix-baseline.md
EOF
    exit 1
fi

echo "row $row — $condition"
if [[ "$row" == D ]]; then
    port_file="$HOME/Library/Application Support/KerNotch/ipc-port"
    if [[ -f "$port_file" ]]; then
        port="$(<"$port_file")"
        echo "post the synthetic working session now, e.g.:"
        echo "  curl -s -o /dev/null -X POST 'http://127.0.0.1:${port}/ai-status' -H 'Content-Type: application/json' \\"
        echo "    -d '{\"schemaVersion\":\"1.0\",\"agentId\":\"claude-code\",\"sessionId\":\"9E1C8518-9DA0-4E93-8313-2637D4E5769F\",\"state\":\"working\",\"detail\":\"matrix row D\",\"timestamp\":\"2026-09-06T00:00:00Z\"}'"
    else
        echo "warning: $port_file not found — enable an agent in settings so the listener publishes its port." >&2
    fi
fi

echo "get the condition going; measuring starts in 5 s"
sleep 5

mkdir -p "$EVIDENCE_DIR"
readonly RAW="$EVIDENCE_DIR/powermetrics-row-$row-$(date +%Y%m%d-%H%M%S).txt"
echo "measuring pid $pid for 60 s (powermetrics)..."
sudo powermetrics --samplers tasks -i 1000 -n 60 > "$RAW"

# powermetrics prints one task table per sample: "Name  PID  CPU_ms/s ...".
# 1000 CPU_ms/s is one full core, so % of one core = avg CPU_ms/s / 10.
readonly SUMMARY="$(awk -v pid="$pid" '
    $1 == "KerNotch" { total += $3; samples += 1 }
    END {
        if (samples > 0)
            printf "%.2f%% of one core over %d samples", total / samples / 10, samples
        else
            print "no KerNotch rows parsed — read the raw capture"
    }' "$RAW")"

readonly LINE="| $row | $(date '+%Y-%m-%d %H:%M') | $SUMMARY | $(basename "$RAW") |"
echo "$LINE" >> "$EVIDENCE_DIR/idle-matrix-baseline.md"
echo "$LINE"
echo "raw capture: $RAW"
