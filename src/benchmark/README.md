# Benchmark — Mohshinsha Harunsha Shahmadar (G25AIT1093)

**Status:** stub — implement `benchmark.cu`

## Build

```bash
make benchmark
```

## Run

```bash
./build/benchmark <data_dir>
```

## Deliverables

- CUDA event timing for kernel launch
- Hashes/sec and GB/s (with and without H↔D transfer)
- CPU OpenSSL baseline comparison

See [TASKS.md](../../TASKS.md) and [IO_CONTRACT.md](../../IO_CONTRACT.md) §7.
