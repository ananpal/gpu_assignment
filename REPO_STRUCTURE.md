# Repository Structure — GPU SHA-256

**Group:** Group 29

Team roster and module assignments: [TASKS.md](TASKS.md).

Build commands: [docs/MAKEFILE_GUIDE.md](docs/MAKEFILE_GUIDE.md) or `make help`.

---

## Planned layout (module owners add their files)

```
gpu_assignment/
├── Makefile                  # build system (M5) — present
├── scripts/run_all.sh          # pipeline wrapper — present
├── docs/MAKEFILE_GUIDE.md      # make command guide — present
├── IO_CONTRACT.md              # data format spec (M1)
├── TASKS.md                    # team roster + timeline
│
├── include/                    # added by M1 / shared — not in repo yet
├── src/
│   ├── cpu_reference/          # M2
│   ├── kernel/                 # M1
│   ├── validate/               # M4
│   └── benchmark/              # M5
├── data/                       # generated at runtime (gitignored)
└── results/                    # large-scale run output
```

Run `make status` to see which source files are still missing.

---

## Git workflow

1. Work on a branch per module: `kernel-m1`, `cpu-m2`, `validate-m4`, `bench-m5`.
2. Open a Pull Request; merge to `main` after review.
3. Pull `main` before each session.

---

## Build targets

```
make help
make status
make pipeline
make cpu_reference | kernel | validate | benchmark
make all
make run N=1000000
```
