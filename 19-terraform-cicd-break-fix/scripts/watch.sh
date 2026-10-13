#!/usr/bin/env bash
# Hit the app every 5 seconds and print the status code, so you can see the
# outage start and end. Ctrl+C to stop.
set -uo pipefail
cd "$(dirname "$0")/../terraform"
url=$(terraform output -raw app_url)
while true; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$url/health")
  echo "$(date -u +%H:%M:%S) UTC  $code"
  sleep 5
done
