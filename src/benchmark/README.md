# src/benchmark — Throughput benchmarks

**Status:** done

Times GPU vs CPU and reports throughput for the report comparison.

## Files
- `benchmark.cpp` — plain C++ driver (like `validate.cpp`). Times OpenSSL CPU
  baseline vs `sha256_gpu_hash()` from `include/sha256_gpu.hpp`. Links
  `src/kernel/sha256_gpu.cu`.

## Build & run
```
make benchmark
./build/benchmark data
```

Or run the full pipeline:
```
make run N=100000
```

## Notes
- Calls **`sha256_gpu_hash()`** through the shared API — does not launch kernels directly.
- Prints **CPU and GPU** rows plus speedup for the report.
- Warm up with one throwaway `sha256_gpu_hash()` before timing.
- Mudrik runs at scale (1K→10M) on the GPU machine; output goes in `results/`.
