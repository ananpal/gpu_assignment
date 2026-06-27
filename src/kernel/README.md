# src/kernel — CUDA SHA-256 kernel

**Owner:** Anand · **Status:** in progress

The GPU program: hashes many messages in parallel, one thread per message.

## Files
- `sha256_single.cu` — stepping stone: hashes ONE message (proves the math on GPU).
- `sha256_multi.cu` — smoke test: hashes 4 hardcoded messages, prints PASS/FAIL.
- `sha256_gpu.cu` — **the deliverable**: loads the dataset from `data/`, hashes all
  messages, writes `data/gpu_digests.bin`, and (if present) verifies against
  `data/expected_digests.bin`. Scale-safe (`size_t` sizes, `CUDA_CHECK`, summary output).
- The shared SHA-256 device code lives in [`../../include/sha256.cuh`](../../include/sha256.cuh).

## Build & run (Colab or GPU machine)
```
# 4-message smoke test:
nvcc sha256_multi.cu -o sha256_multi && ./sha256_multi          # expect ALL PASS

# full dataset (after the CPU reference has written data/):
nvcc sha256_gpu.cu -o sha256_gpu && ./sha256_gpu data           # expect VALIDATION: ALL MATCH
```

## Notes for anyone covering this
- The SHA-256 math (`sha256_transform`, `sha256_hash`) is verified — don't touch it.
- Only the kernel indexing + host load/save plumbing is the real work here.
- Data format: see [../../IO_CONTRACT.md](../../IO_CONTRACT.md).
