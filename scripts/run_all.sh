#!/usr/bin/env bash
# run_all.sh — run the whole pipeline end-to-end.
# Usage: ./scripts/run_all.sh [N]      (N = number of messages, default 100000)
set -e

N="${1:-100000}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo ">>> [1/4] Generate dataset + CPU reference (N=$N)"
# TODO: switch to the C++ build once cpu_reference.cpp is ready:
#   ./build/cpu_reference "$N"
python src/cpu_reference/generate_dataset.py "$N"

echo ">>> [2/4] Run GPU kernel -> data/gpu_digests.bin"
# TODO: ./build/sha256_gpu        (once sha256_gpu.cu loads the dataset)
echo "    (pending sha256_gpu.cu)"

echo ">>> [3/4] Validate GPU vs CPU"
# TODO: ./build/validate
echo "    (pending validate.cpp)"

echo ">>> [4/4] Benchmark GPU vs CPU"
# TODO: ./build/benchmark
echo "    (pending benchmark.cu)"

echo ">>> done."
