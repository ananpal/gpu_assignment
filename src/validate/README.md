# src/validate — Correctness validation

**Owner:** Arundhati · **Status:** to build

Compares the GPU output against the CPU reference, slot by slot.

## Files
- `validate.cpp` — *(to build)* reads `data/gpu_digests.bin` (kernel) and
  `data/expected_digests.bin` (cpu_reference), compares each 32-byte digest.

## Build & run
```
g++ validate.cpp -o validate
./validate            # reports ALL MATCH / N MISMATCHES + first mismatch index
```

## Notes for anyone covering this
- `memcmp` on 32-byte chunks is the whole comparison.
- Edge-case suite to add: empty, 1 byte, exactly 55 / 56 / 64 bytes, a multi-block message —
  these are where SHA padding bugs hide.
- Fully independent: testable against `cpu_reference` output before the kernel is done.
