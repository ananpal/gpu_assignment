# src/kernel — CUDA SHA-256 kernel

**Owner:** Anand · **Status:** in progress

The GPU program: hashes many messages in parallel, one thread per message.

## Files
- `sha256_single.cu` — stepping stone: hashes ONE message (proves the math on GPU).
- `sha256_multi.cu` — smoke test: hashes 4 hardcoded messages, prints PASS/FAIL.
- `sha256_gpu.cu` — **the engine**: implements the reusable host API
  `sha256_gpu_hash(...)` (declared in [`../../include/sha256_gpu.hpp`](../../include/sha256_gpu.hpp)).
  No `main()`, so the validator / benchmark can link it and call it directly.
  Scale-safe (`size_t` sizes, `CUDA_CHECK`).
- `run_gpu.cu` — standalone driver: loads `data/`, calls the engine, writes
  `data/gpu_digests.bin`, and verifies against `data/expected_digests.bin`.
- Shared device code: [`../../include/sha256.cuh`](../../include/sha256.cuh).

## The API (call the GPU from another tool)
```cpp
#include "sha256_gpu.hpp"
std::vector<unsigned char> digests =
    sha256_gpu_hash(messages, total_bytes, offsets, lengths, num_messages);
// returns num_messages*32 bytes; digest i at [i*32 .. i*32+31]
// build:  nvcc your_tool.cpp src/kernel/sha256_gpu.cu -o your_tool
```
This is how the **validator pipeline** runs the GPU: include the header, call the
function, compare the result to the CPU reference — no kernel knowledge needed.

## Build & run (Colab or GPU machine)
```
# 4-message smoke test:
nvcc sha256_multi.cu -o sha256_multi && ./sha256_multi          # expect ALL PASS

# full dataset (engine + driver):
nvcc run_gpu.cu sha256_gpu.cu -o sha256_gpu && ./sha256_gpu data  # expect VALIDATION: ALL MATCH
```

## Notes for anyone covering this
- The SHA-256 math (`sha256_transform`, `sha256_hash`) is verified — don't touch it.
- The engine (`sha256_gpu.cu`) has no `main()` on purpose — keep it linkable.
- Data format: see [../../IO_CONTRACT.md](../../IO_CONTRACT.md).
