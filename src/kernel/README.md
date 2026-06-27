# GPU Kernel — Anand Pal (G25AIT1019)

**Status:** stub — implement `sha256_gpu.cu` and `include/sha256.cuh`

## Build

```bash
make kernel
```

## Run

```bash
./build/sha256_gpu <data_dir>
```

## Deliverables

- CUDA kernel: one thread per message
- Reads dataset from `<data_dir>/`
- Writes `<data_dir>/gpu_digests.bin`

See [IO_CONTRACT.md](../../IO_CONTRACT.md) §2–§3.
