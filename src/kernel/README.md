# src/kernel — CUDA SHA-256 kernel

**Owner:** Anand · **Status:** in progress

The GPU program: hashes many messages in parallel, one thread per message.

## Files
- `sha256_single.cu` — stepping stone: hashes ONE message (proves the math on GPU).
- `sha256_multi.cu` — hashes MANY messages (4 hardcoded) — the working base.
- `sha256_gpu.cu` — *(to build)* final version: loads the dataset from `data/`,
  runs the kernel, writes `data/gpu_digests.bin`. Start from `sha256_multi.cu`.

## Build & run (Colab or GPU machine)
```
nvcc sha256_multi.cu -o sha256_multi && ./sha256_multi   # expect ALL PASS
```

## Notes for anyone covering this
- The SHA-256 math (`sha256_transform`, `sha256_hash`) is verified — don't touch it.
- Only the kernel indexing + host load/save plumbing is the real work here.
- Data format: see [../../IO_CONTRACT.md](../../IO_CONTRACT.md).
