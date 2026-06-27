#!/usr/bin/env bash
# Wrapper for Makefile pipeline target (make run).
set -euo pipefail
cd "$(dirname "$0")/.."
make run N="${1:-1000}" DATA_DIR="${2:-data}"
