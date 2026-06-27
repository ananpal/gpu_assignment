# include/ — Shared code

| File | What it is |
|---|---|
| `sha256.cuh` | Device SHA-256: `__constant__ K[]`, macros, `sha256_transform`, `sha256_hash`, `sha256_kernel`. Include in exactly one `.cu` per compiled program. |
| `sha256_gpu.hpp` | Host API: declares `sha256_gpu_hash(...)`. Plain C++ — any `.cpp` or `.cu` can include it. |

Both headers are owned by Anand. Any change goes through him and through [IO_CONTRACT.md](../IO_CONTRACT.md).
