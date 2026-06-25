# Cryptography on GPU

Parallel **SHA-256** hashing on the GPU using **CUDA** — a team project (5 members, 3 days).

We compute SHA-256 digests for millions of independent messages in parallel
(one GPU thread per message), verify the GPU output against a trusted CPU
reference (`hashlib`), and benchmark GPU vs CPU throughput.

## Repository contents

| File | What it is | Owner |
|---|---|---|
| [IO_CONTRACT.md](IO_CONTRACT.md) | **Read this first.** The agreed data formats and function signatures everyone codes against. | M1 |
| [colab_starter.ipynb](colab_starter.ipynb) | Day-1 setup notebook — verifies your Colab GPU compiles & runs CUDA. | All |

## Getting started (every member, Day 1)

1. Open [Google Colab](https://colab.research.google.com) → **File → Upload notebook** → `colab_starter.ipynb`.
2. **Runtime → Change runtime type → GPU → Save.**
3. Run all cells. If the last cell prints `SETUP OK`, you're ready.
4. Read [IO_CONTRACT.md](IO_CONTRACT.md) before writing any code.

## Team tasks

| Member | Task |
|---|---|
| M1 | Algorithm choice & spec (I/O contract) |
| M2 | CPU reference (`hashlib`) + test vectors + dataset generator |
| M3 | CUDA SHA-256 kernel (one thread per message) |
| M4 | Correctness validation (GPU output vs CPU reference) |
| M5 | Throughput benchmarks (hashes/sec, GB/s, GPU vs CPU scaling) |
| All | Final report + security note |

## Plan

- **Day 1:** Setup + agree the I/O contract. M2/M3/M4 start in parallel.
- **Day 2:** Make the kernel **correct** — GPU output == CPU output on the full dataset.
- **Day 3:** Benchmark, light optimization, write the report.

**Golden rule:** correctness before speed. Test the `""` and `"abc"` vectors first.
