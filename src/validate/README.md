# src/validate — Correctness validation

**Owner:** Arundhati · **Status:** in progress

Confirms the GPU SHA-256 output matches a trusted CPU reference (OpenSSL).

## Files
- `validate.cpp` — runs two checks:
  1. **Edge-case suite** — empty, 1 byte, exactly 55 / 56 / 64 bytes (block
     boundaries), a multi-block message, and the NIST vectors.
  2. **Dataset check** — loads `data/`, hashes every message on the GPU via the
     shared API (`sha256_gpu_hash`), and compares slot-by-slot against the CPU
     reference (or `data/expected_digests.bin` if present). Reports the first mismatch.

## Build & run
```
# needs OpenSSL headers: apt-get install -y libssl-dev
nvcc validate.cpp ../kernel/sha256_gpu.cu -o validate -lssl -lcrypto
./validate data        # edge cases always run; dataset check runs if data/ exists
```
Exit code 0 = all passed, 1 = something failed.

## Notes for anyone covering this
- It calls the GPU through `include/sha256_gpu.hpp` — no CUDA knowledge needed here.
- The 55 / 56 / 64-byte cases are the padding boundaries; keep them in the suite.
- Depends on the kernel engine `../kernel/sha256_gpu.cu` (the `sha256_gpu_hash` API).
