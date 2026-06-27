# src/kernel — GPU SHA-256

**Owner:** Anand

## Files

| File | Purpose |
|---|---|
| `sha256_gpu.cu` | **Engine** — implements `sha256_gpu_hash()`. No `main()`, links into other tools. |
| `hash_dataset.cu` | **Driver** — loads `data/`, calls the engine, writes `gpu_digests.bin`. |
| `sha256_smoke_test.cu` | **Smoke test** — hashes 4 known messages, prints PASS/FAIL. Run this first. |
| `../../include/sha256.cuh` | Shared device code (constants, transform, hash, kernel). |
| `../../include/sha256_gpu.hpp` | Host API declaration. |

## Build & run

```bash
# smoke test — run this before anything else:
nvcc sha256_smoke_test.cu -o sha256_smoke_test && ./sha256_smoke_test

# hash a full dataset:
nvcc hash_dataset.cu sha256_gpu.cu -o hash_dataset && ./hash_dataset data
```

## Using the GPU from another tool

```cpp
#include "sha256_gpu.hpp"

// throws std::runtime_error on CUDA failure
std::vector<unsigned char> digests =
    sha256_gpu_hash(messages, total_bytes, offsets, lengths, num_messages);
// digest for message i: digests[i*32 .. i*32+31]
```

Build: `nvcc your_tool.cpp sha256_gpu.cu -o your_tool`

## Notes

- The SHA-256 math in `sha256.cuh` is verified against all NIST vectors — don't modify it.
- The engine throws `std::runtime_error` on any CUDA error (never `exit()`), so callers can catch it.
- Data format: [IO_CONTRACT.md](../../IO_CONTRACT.md).
