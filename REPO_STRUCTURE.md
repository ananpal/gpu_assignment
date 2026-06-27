# Repo Structure

**Design principle:** one folder per member, shared interfaces defined once in `include/`.

## Why it's set up this way

- **Folder per member** — each person edits only files in their folder, so parallel pushes almost never conflict.
- **Shared `include/`** — the data format and the GPU API are defined once. The writer (Karan) and readers (Anand, Arundhati) call the same code, so the format can't drift.
- **Per-folder READMEs** — every folder documents its status and build command so anyone can cover for an absent teammate without asking.

## Git workflow

1. Create a branch for your change (`git checkout -b my-change`).
2. Push and open a PR — one other member reviews it.
3. **Pull `main` before every session** so you build against the latest code.
4. Never commit `data/*.bin` or compiled binaries (`.gitignore` handles this).

## Build commands

```bash
# smoke test:
nvcc src/kernel/sha256_smoke_test.cu -o sha256_smoke_test

# hash a dataset:
nvcc src/kernel/hash_dataset.cu src/kernel/sha256_gpu.cu -o hash_dataset

# validate:
nvcc src/validate/validate.cpp src/kernel/sha256_gpu.cu -o validate -lssl -lcrypto

# CPU reference + dataset generator:
g++ src/cpu_reference/cpu_reference.cpp -o cpu_reference -lssl -lcrypto
```

## Pipeline (end-to-end)

```
cpu_reference <N>       # generate data/ + expected_digests.bin  (Karan)
hash_dataset data       # GPU hashes → gpu_digests.bin           (Anand)
validate data           # compare GPU vs CPU                      (Arundhati)
benchmark data          # hashes/sec, GB/s, scaling curve        (Mohshinsha/Mudrik)
```
