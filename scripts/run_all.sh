#!/usr/bin/env bash
set -euo pipefail

NUM_MESSAGES="${1:-1000}"
DATA_DIR="${2:-data}"
BUILD_DIR="build"

mkdir -p "${DATA_DIR}" results

make all

echo "==> Generating dataset (${NUM_MESSAGES} messages)..."
"${BUILD_DIR}/cpu_reference" "${NUM_MESSAGES}" "${DATA_DIR}"

echo "==> Running GPU kernel..."
"${BUILD_DIR}/sha256_gpu" "${DATA_DIR}"

echo "==> Validating GPU output..."
"${BUILD_DIR}/validate" "${DATA_DIR}"

echo "==> Benchmarking..."
"${BUILD_DIR}/benchmark" "${DATA_DIR}"

echo "Pipeline complete."
