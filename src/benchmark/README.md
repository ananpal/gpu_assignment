# src/benchmark — Throughput benchmarks

**Owner:** Mohshinsha · **Status:** to build

Times GPU vs CPU and reports throughput + scaling.

## Files
- `benchmark.cu` — *(to build)* CUDA-event timing around the kernel; also times the
  CPU baseline (OpenSSL, single-threaded). Reports hashes/sec and GB/s.

## Build & run
```
nvcc benchmark.cu -o benchmark && ./benchmark
```

## Notes for anyone covering this
- Use `cudaEventCreate/Record/Synchronize/ElapsedTime` around the launch.
- **Warm up** with one throwaway run before timing.
- Report time both with and without host↔device transfer.
- Mudrik runs this at scale (1K→10M) on the GPU machine; output goes in `results/`.
