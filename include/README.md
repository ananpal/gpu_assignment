# include — Shared code (the glue)

**Owner:** Anand (shared) · **Status:** to build

Code used by more than one module, defined **once** so it can't drift.

## Files (to build)
- `sha256.cuh` — the device SHA-256 (`__constant__ K[]`, macros, `sha256_transform`,
  `sha256_hash`), lifted from `src/kernel/sha256_multi.cu`. Included by `kernel/` and `benchmark/`.
- `dataset_io.hpp` — read/write the `data/*.bin` files (the IO_CONTRACT §4 format).
  Used by `cpu_reference` (writer) and `kernel`/`validate` (readers).

## Why this matters
Because the writer and readers call the **same** `dataset_io.hpp`, the on-disk format
is guaranteed identical across modules — this kills the most likely integration bug.
