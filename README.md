# Cryptography on GPU — Group 29

Parallel **SHA-256** hashing on the GPU using **CUDA**. One GPU thread per message, millions of messages in parallel. Correctness verified against OpenSSL. Benchmarked GPU vs CPU throughput.

## Repo layout

```
include/
  sha256.cuh          device SHA-256 (constants, transform, hash, kernel)
  sha256_gpu.hpp      host API declaration

src/kernel/           Anand
  sha256_gpu.cu       engine — implements sha256_gpu_hash(), no main()
  hash_dataset.cu     driver — load data/, call engine, write gpu_digests.bin
  sha256_smoke_test.cu quick 4-message correctness check

src/cpu_reference/    Karan
  cpu_reference.cpp   C++/OpenSSL dataset generator + trusted CPU reference
  generate_dataset.py Python prototype (reference for the C++ port)

src/validate/         Arundhati
  validate.cpp        edge-case suite + full dataset GPU-vs-CPU check

src/benchmark/        Mohshinsha
  benchmark.cpp       CUDA vs CPU timing via sha256_gpu_hash API

scripts/
  colab_starter.ipynb GPU setup check (Colab)
  run_all.sh          end-to-end pipeline

data/                 generated datasets — gitignored
results/              Mudrik's benchmark output + charts
docs/                 day-wise plan (temporary)
```

## Key docs

| Doc | What it is |
|---|---|
| [IO_CONTRACT.md](IO_CONTRACT.md) | **Read first.** Data formats and function signatures everyone codes against. |
| [TASKS.md](TASKS.md) | Who owns what and the rules that keep everyone unblocked. |

## Getting started

1. Open Colab → **File → Upload notebook** → `scripts/colab_starter.ipynb`.
2. **Runtime → Change runtime type → GPU → Save.**
3. Run all cells — last cell prints `SETUP OK` if ready.
4. Read [IO_CONTRACT.md](IO_CONTRACT.md), find your task in [TASKS.md](TASKS.md).

## Build

```bash
# smoke test (verify the math works):
nvcc src/kernel/sha256_smoke_test.cu -o sha256_smoke_test && ./sha256_smoke_test

# hash a dataset (after cpu_reference generates data/):
nvcc src/kernel/hash_dataset.cu src/kernel/sha256_gpu.cu -o hash_dataset && ./hash_dataset data

# validate GPU vs CPU:
nvcc src/validate/validate.cpp src/kernel/sha256_gpu.cu -o validate -lssl -lcrypto && ./validate data
```

**Rule:** correctness before speed. Run the smoke test and validator before benchmarking.
