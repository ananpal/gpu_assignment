# Cryptography on GPU

Parallel **SHA-256** hashing on the GPU using **CUDA** — a team project (Group 29).

We compute SHA-256 digests for millions of independent messages in parallel
(one GPU thread per message), verify the GPU output against a trusted CPU
reference (OpenSSL), and benchmark GPU vs CPU throughput.

## Layout

```
include/            shared code (sha256.cuh, dataset_io.hpp)
src/kernel/         CUDA SHA-256 kernel        (Anand)
src/cpu_reference/  dataset generator + reference (Karan)
src/validate/       correctness checker        (Arundhati)
src/benchmark/      throughput timing          (Mohshinsha)
scripts/            colab_starter.ipynb, run_all.sh
data/               generated datasets (gitignored)
results/            benchmark output + charts  (Mudrik)
docs/               day-wise plan, report
```

Each `src/` folder has its own README (status + how to build/run).
See [REPO_STRUCTURE.md](REPO_STRUCTURE.md) for the full rationale.

## Key docs

| Doc | What it is |
|---|---|
| [IO_CONTRACT.md](IO_CONTRACT.md) | **Read first.** The data formats & function signatures everyone codes against. |
| [TASKS.md](TASKS.md) | Who owns what + the rules that keep everyone unblocked. |
| [REPO_STRUCTURE.md](REPO_STRUCTURE.md) | The modular folder design. |

## Getting started (every member)

1. Open [Google Colab](https://colab.research.google.com) → **File → Upload notebook** → `scripts/colab_starter.ipynb`.
2. **Runtime → Change runtime type → GPU → Save.**
3. Run all cells. If the last cell prints `SETUP OK`, you're ready.
4. Read [IO_CONTRACT.md](IO_CONTRACT.md) before writing any code.
5. Find your task in [TASKS.md](TASKS.md) and work in your folder.

**Golden rule:** correctness before speed. Test the `""` and `"abc"` vectors first.
