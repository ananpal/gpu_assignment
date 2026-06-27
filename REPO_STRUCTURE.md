# Repository Structure — GPU SHA-256

**Group:** Group 29
**Owner of setup:** Mudrik Kaushik (creates the repo + skeleton Friday, first thing).
**Goal:** every member owns a folder, pushes independently with near-zero merge
conflicts, and — if someone is unavailable — anyone can pick up their piece because
each folder is self-documented and the shared interfaces are defined once.

---

## The two ideas that make this modular

1. **Folder per member.** Each person's code lives in its own folder. Because nobody
   edits the same files, individual pushes to `main` almost never conflict.
2. **Shared headers = "contract as code."** The data format isn't just described in
   `IO_CONTRACT.md` — it's *implemented once* in `include/dataset_io.hpp`. Karan (writer)
   and Anand/Arundhati (readers) all call the same functions, so the format can never
   drift. This is what lets people chip in: the interface is one file, clearly defined.

---

## Folder layout

```
gpu_assignment/
├── README.md                 # overview, build/run, team table
├── IO_CONTRACT.md            # data format spec            (owner: Anand)
├── TASKS.md                  # who does what + timeline
├── REPO_STRUCTURE.md         # this file
├── Makefile                  # builds every module          (owner: Mohshinsha)
├── .gitignore                # ignores data/*.bin, binaries, build/
│
├── include/                  # SHARED code everyone depends on
│   ├── sha256.cuh            # device SHA-256 functions      (owner: Anand)
│   └── dataset_io.hpp        # read/write the .bin files     (shared)
│
├── src/
│   ├── common/
│   │   └── dataset_io.cpp    # dataset I/O implementation
│   ├── kernel/               # Anand — the GPU program
│   │   ├── sha256_gpu.cu
│   │   └── README.md         # status + how to build/run
│   ├── cpu_reference/        # Karan — dataset generator + CPU reference
│   │   ├── cpu_reference.cpp
│   │   └── README.md
│   ├── validate/             # Arundhati — correctness checker
│   │   ├── validate.cpp
│   │   └── README.md
│   └── benchmark/            # Mohshinsha — timing harness
│       ├── benchmark.cu
│       └── README.md
│
├── scripts/
│   ├── colab_starter.ipynb   # GPU setup check (Colab users)
│   └── run_all.sh            # run the whole pipeline end-to-end
│
├── data/                     # generated datasets — GITIGNORED (too big to commit)
│   └── .gitkeep
│
├── results/                  # Mudrik — benchmark numbers, charts, run logs
│   └── .gitkeep
│
└── docs/
    └── report/               # report, one file per member (no merge conflicts)
        ├── 00_overview.md
        ├── 01_algorithm.md       # Anand
        ├── 02_cpu_reference.md   # Karan
        ├── 03_kernel.md          # Anand
        ├── 04_validation.md      # Arundhati
        ├── 05_benchmark.md       # Mohshinsha / Mudrik
        └── 06_security.md        # all
```

---

## Why this supports "push individually" and "chip in if someone is away"

| Need | How the structure provides it |
|---|---|
| Push without conflicts | Each member edits only files in **their own folder** → independent commits |
| Cover for an absent member | Every folder has a **README** (status + how to build/run); interfaces are in `include/` |
| Format never drifts | Writer and readers share **one** `dataset_io.hpp` — change it once, everyone updates |
| Anyone can verify the whole thing | `scripts/run_all.sh` runs generate → kernel → validate → benchmark in order |
| No huge files in Git | `data/` and binaries are **gitignored**; only code + small results are committed |

---

## The shared `include/` files (the glue)

**`include/dataset_io.hpp`** — defines the file format ONCE:
```cpp
// Reads/writes the I/O-contract §4 files. Used by Karan, Anand, and Arundhati.
struct Dataset {
    std::vector<unsigned char> messages;  // packed
    std::vector<int> offsets;
    std::vector<int> lengths;
    int num_messages;
};
void write_dataset(const std::string& dir, const Dataset& d,
                   const std::vector<unsigned char>& digests);  // Karan uses this
Dataset read_dataset(const std::string& dir);                   // Anand/Arundhati use this
std::vector<unsigned char> read_digests(const std::string& path);
void write_digests(const std::string& path, const std::vector<unsigned char>& digests);
```
Because everyone calls these, the on-disk format is guaranteed identical across modules.

**`include/sha256.cuh`** — the device `__constant__ K[]`, macros, `sha256_transform`,
`sha256_hash`. Both `kernel/` and `benchmark/` `#include` it,
so the hash math exists in exactly one place.

---

## Git workflow (keep it simple)

Folder isolation means you can commit straight to `main` with little conflict risk, but
use light branches for safety + review:

1. Each member works on a branch named for their piece:
   `kernel-anand`, `cpu-karan`, `validate-arundhati`, `bench-mohshinsha`.
2. Push your branch, open a Pull Request, one other member glances at it, merge to `main`.
3. **Pull `main` before you start each session** so you have everyone's latest (Mudrik
   especially — his big runs need the newest code).
4. Never commit `data/*.bin` or compiled binaries (the `.gitignore` handles this).

> Too time-pressed for PRs? Then commit directly to `main` — folder isolation keeps it
> safe — but still **pull before you push**.

---

## Build targets (Mohshinsha's `Makefile`)

One command per module so anyone can build any piece:
```
make cpu_reference   # builds Karan's generator  (g++ ... -lssl -lcrypto)
make kernel          # builds Anand's GPU program (nvcc)
make validate        # builds Arundhati's checker (g++)
make benchmark       # builds Mohshinsha's timing (nvcc)
make all             # everything
```

`scripts/run_all.sh` then chains them:
```
cpu_reference 1000000     # generate dataset + reference
kernel                    # produce gpu_digests.bin
validate                  # ALL MATCH?
benchmark                 # GPU vs CPU numbers
```
