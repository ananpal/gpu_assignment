# Cryptography on GPU — Group 29

Parallel **SHA-256** hashing on the GPU using **CUDA** — a team project (5 members, 3 days).

**Assignment choice:** SHA hashing — compute digests in parallel for large datasets.

We compute SHA-256 digests for millions of independent messages in parallel
(one GPU thread per message), verify the GPU output against a trusted CPU
reference (OpenSSL C++), and benchmark GPU vs CPU throughput.

See [TASKS.md](TASKS.md) for the team roster, timeline, and per-module deliverables.

## Repository contents

| File | What it is |
|---|---|
| [IO_CONTRACT.md](IO_CONTRACT.md) | **Read this first.** Data formats and function signatures |
| [TASKS.md](TASKS.md) | Team task plan and timeline |
| [REPO_STRUCTURE.md](REPO_STRUCTURE.md) | Folder layout, git workflow, build targets |
| [docs/MAKEFILE_GUIDE.md](docs/MAKEFILE_GUIDE.md) | Guide to all `make` commands |
| [colab_starter.ipynb](colab_starter.ipynb) | Day-1 Colab GPU setup check |

## Getting started (every member, Day 1)

1. Open [Google Colab](https://colab.research.google.com) → **File → Upload notebook** → `colab_starter.ipynb`.
2. **Runtime → Change runtime type → GPU → Save.**
3. Run all cells. If the last cell prints `SETUP OK`, you're ready.
4. Read [IO_CONTRACT.md](IO_CONTRACT.md) before writing any code.
5. Run `make status` to see which module files are still missing.

## Build & run (GPU machine or Colab)

```bash
# Install OpenSSL dev headers (Ubuntu/Colab)
sudo apt-get install -y libssl-dev

make help
make status
make all
./scripts/run_all.sh 1000    # small test: 1K messages
./scripts/run_all.sh 1000000 # large run: 1M messages
```

Pipeline: `cpu_reference` → `kernel` → `validate` → `benchmark`

## Plan

- **Day 1:** Setup + lock the I/O contract. M2/M1/M4 start in parallel.
- **Day 2:** Make the kernel **correct** — GPU output == CPU output on the full dataset.
- **Day 3:** Benchmark, light optimization, write the report.

**Golden rule:** correctness before speed. Test the `""` and `"abc"` vectors first.
