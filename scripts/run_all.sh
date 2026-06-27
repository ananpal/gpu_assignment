#!/usr/bin/env bash
# Wrapper for Mohshinsha's Makefile pipeline target.
set -euo pipefail
cd "$(dirname "$0")/.."
make run N="${1:-1000}" DATA_DIR="${2:-data}"
