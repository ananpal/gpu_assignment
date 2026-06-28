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
./build/benchmark data --output results/my_run.csv
```

Or run the full pipeline:
```
make run N=100000
```

## Report output (CSV)

Each run writes:
- `results/benchmark_<num_messages>.csv` — single-run snapshot (default)
- `results/benchmark_summary.csv` — appended row for scaling runs (1K → 10M)

Columns: `data_dir, num_messages, input_bytes, cpu_ms, cpu_hashes_per_sec,
cpu_gbps, gpu_ms, gpu_hashes_per_sec, gpu_gbps, speedup`

Use `benchmark_summary.csv` for report tables and charts.

## Notes
- Calls **`sha256_gpu_hash()`** through the shared API — does not launch kernels directly.
- Warm up with one throwaway `sha256_gpu_hash()` before timing.
- Mudrik runs at scale on the GPU machine; download `results/*.csv` from Colab for the report.
