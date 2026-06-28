#!/usr/bin/env bash
# run_all.sh — run the whole pipeline end-to-end.
# Usage: ./scripts/run_all.sh [N]      (N = number of messages, default 100000)
set -e

N="${1:-100000}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

make all
make run N="$N"

echo ">>> done."
