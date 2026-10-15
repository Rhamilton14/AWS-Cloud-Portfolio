#!/usr/bin/env bash
# Measure Lambda cold starts from CloudShell.
#
# For each memory size: change the configuration (which forces Lambda to
# start a new execution environment), invoke once (cold), then invoke again
# (warm). Each invoke records the REPORT line Lambda returns in the tail of
# the log, plus the round-trip latency seen by the client.
#
# Usage:  ./measure-cold-starts.sh <function-name> [runs-per-size] [memory sizes...]
# Example: ./measure-cold-starts.sh cold-start-python 5 128 512 1024 1769
# Output: results-<function-name>.csv

set -euo pipefail

FUNCTION="${1:?usage: $0 <function-name> [runs-per-size] [memory sizes...]}"
RUNS="${2:-5}"
shift $(( $# >= 2 ? 2 : 1 ))
if [ $# -gt 0 ]; then SIZES=("$@"); else SIZES=(128 512 1024 1769); fi

OUT="results-${FUNCTION}.csv"
echo "function,memory_mb,run,kind,init_ms,duration_ms,billed_ms,client_ms" > "$OUT"

# Keep the function's existing environment variables, and add a nonce
current_env() {
  aws lambda get-function-configuration --function-name "$FUNCTION" \
    --query 'Environment.Variables' --output json
}

invoke() {
  local kind="$1" memory="$2" run="$3"
  local start end log report
  start=$(date +%s%N)
  log=$(aws lambda invoke --function-name "$FUNCTION" --log-type Tail \
    --cli-binary-format raw-in-base64-out --payload '{}' \
    --query 'LogResult' --output text /dev/null | base64 -d)
  end=$(date +%s%N)
  report=$(grep '^REPORT' <<< "$log")
  python3 - "$FUNCTION" "$memory" "$run" "$kind" "$(( (end - start) / 1000000 ))" "$report" >> "$OUT" <<'PY'
import re, sys
fn, mem, run, kind, client_ms, report = sys.argv[1:]
def field(name):
    m = re.search(rf"{name}: ([\d.]+) ms", report)
    return m.group(1) if m else ""
print(",".join([fn, mem, run, kind, field("Init Duration"),
                field(r"\tDuration"), field("Billed Duration"), client_ms]))
PY
}

for memory in "${SIZES[@]}"; do
  for run in $(seq 1 "$RUNS"); do
    env_json=$(current_env | python3 -c '
import json, sys, time
v = json.load(sys.stdin) or {}
v["COLD_START_NONCE"] = str(time.time_ns())
print(json.dumps({"Variables": v}))')
    aws lambda update-function-configuration --function-name "$FUNCTION" \
      --memory-size "$memory" --environment "$env_json" > /dev/null
    aws lambda wait function-updated --function-name "$FUNCTION"

    invoke cold "$memory" "$run"
    invoke warm "$memory" "$run"
    echo "memory=${memory}MB run=${run} done"
  done
done

echo
echo "Averages (ms):"
python3 - "$OUT" <<'PY'
import csv, sys
from collections import defaultdict
rows = list(csv.DictReader(open(sys.argv[1])))
groups = defaultdict(list)
for r in rows:
    groups[(int(r["memory_mb"]), r["kind"])].append(r)
avg = lambda rs, k: sum(float(r[k]) for r in rs if r[k]) / max(1, sum(1 for r in rs if r[k]))
print(f"{'memory':>7} {'kind':>5} {'init':>8} {'duration':>9} {'billed':>7} {'client':>7}")
for (mem, kind), rs in sorted(groups.items()):
    print(f"{mem:>7} {kind:>5} {avg(rs,'init_ms'):>8.1f} {avg(rs,'duration_ms'):>9.1f} "
          f"{avg(rs,'billed_ms'):>7.0f} {avg(rs,'client_ms'):>7.0f}")
PY
echo "Raw results: $OUT"
