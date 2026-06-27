# Cryptography on GPU — Group 29

Parallel **SHA-256** hashing on the GPU using **CUDA** — a team project (5 members, 3 days).

**Assignment choice:** SHA hashing — compute digests in parallel for large datasets.

We compute SHA-256 digests for millions of independent messages in parallel
(one GPU thread per message), verify the GPU output against a trusted CPU
reference (OpenSSL C++), and benchmark GPU vs CPU throughput.

## Team (Group 29)

| Name | Roll No. | Task |
|------|----------|------|
| Anand Pal | G25AIT1019 | I/O contract + CUDA kernel |
| Arundhati | G25AIT1033 | Correctness validation |
| Mohshinsha Harunsha Shahmadar | G25AIT1093 | Benchmark harness + Makefile + report |
| Mudrik Kaushik | G25AIT1096 | Repo setup + large-scale GPU runs |
| Karan Kapoor | G25AIT1233 | CPU reference (OpenSSL) + dataset generator |

See [TASKS.md](TASKS.md) for the full timeline and per-member deliverables.

## Repository contents

| File | What it is | Owner |
|---|---|---|
| [IO_CONTRACT.md](IO_CONTRACT.md) | **Read this first.** Data formats and function signatures everyone codes against. | Anand |
| [TASKS.md](TASKS.md) | Team task plan, timeline, Group 29 roster | All |
| [REPO_STRUCTURE.md](REPO_STRUCTURE.md) | Folder layout, git workflow, build targets | Mudrik |
| [colab_starter.ipynb](colab_starter.ipynb) | Day-1 setup — verifies Colab GPU compiles & runs CUDA | All |

## Getting started (every member, Day 1)

1. Open [Google Colab](https://colab.research.google.com) → **File → Upload notebook** → `colab_starter.ipynb`.
2. **Runtime → Change runtime type → GPU → Save.**
3. Run all cells. If the last cell prints `SETUP OK`, you're ready.
4. Read [IO_CONTRACT.md](IO_CONTRACT.md) before writing any code.

## Build & run (GPU machine or Colab)

```bash
# Install OpenSSL dev headers (Ubuntu/Colab)
sudo apt-get install -y libssl-dev

make all
./scripts/run_all.sh 1000    # small test: 1K messages
./scripts/run_all.sh 1000000 # large run: 1M messages
```

Pipeline: `cpu_reference` → `kernel` → `validate` → `benchmark`

## Plan

- **Day 1:** Setup + lock the I/O contract. Karan/Anand/Arundhati start in parallel.
- **Day 2:** Make the kernel **correct** — GPU output == CPU output on the full dataset.
- **Day 3:** Benchmark, light optimization, write the report.

**Golden rule:** correctness before speed. Test the `""` and `"abc"` vectors first.
