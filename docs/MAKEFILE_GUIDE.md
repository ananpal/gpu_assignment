# Makefile Guide — GPU SHA-256

This project uses a **Makefile** to build each module and to show what is done vs still missing. Run all commands from the **repo root** (`gpu_assignment/`).

```bash
cd gpu_assignment
make <target>
```

If you run plain `make` with no target, it runs **`make help`**.

---

## Quick start

| I want to… | Command |
|------------|---------|
| See all commands | `make` or `make help` |
| Check what files are missing | `make status` |
| See the full pipeline order | `make pipeline` |
| See build-system / benchmark tasks | `make build-system` |
| Build one module | `make cpu_reference` / `kernel` / `validate` / `benchmark` |
| Build everything that exists | `make all` |
| Run the full pipeline | `make run N=1000` |
| Delete compiled binaries | `make clean` |

---

## Information commands (always work)

These do **not** compile code. They only print guidance.

### `make help`

Lists every `make` target and a one-line description.

**Use when:** you forget which commands exist.

---

### `make status`

Shows a checklist of **source files** and **data files**:

- `[ok]` — file exists  
- `[MISS]` — source file not added yet (with the **task** it belongs to)  
- `[----]` — runtime data file not generated yet (normal before first run)

**Example output:**
```
[ok]   include/sha256.cuh  — I/O contract + device SHA-256 helpers
[MISS] src/kernel/sha256_gpu.cu  — CUDA kernel; write gpu_digests.bin
[----] data/messages.bin
```

**Use when:** starting work, or before a team sync, to see what is still missing.

---

### `make pipeline`

Prints the **full pipeline in order** (steps 1–5):

1. CPU reference + dataset generator  
2. CUDA SHA-256 kernel  
3. Correctness validation  
4. Throughput benchmark  
5. Large-scale runs on GPU machine  

For each step it shows:

- Shell commands to run  
- Source files required  
- Files created under `data/`  
- **Expected output** when that step is implemented  

**Use when:** you need to understand how modules connect end-to-end. See also [IO_CONTRACT.md](../IO_CONTRACT.md).

---

### `make build-system`

Lists tasks and files for:

- Maintaining the **Makefile**  
- Implementing **`src/benchmark/benchmark.cu`**  
- Assembling **`docs/report/`**  

**Use when:** working on the build system, benchmark harness, or final report.

---

## Build commands (compile one module)

These try to compile a module into `build/`. If the source file is **missing**, they print the **tasks** and **expected output**, then exit with an error (exit code 1).

| Command | Builds | Source file needed | Output binary |
|---------|--------|-------------------|---------------|
| `make cpu_reference` | CPU reference + dataset tool | `src/cpu_reference/cpu_reference.cpp` | `build/cpu_reference` |
| `make kernel` | GPU SHA-256 program | `src/kernel/sha256_gpu.cu` | `build/sha256_gpu` |
| `make validate` | Correctness checker | `src/validate/validate.cpp` | `build/validate` |
| `make benchmark` | Timing harness | `src/benchmark/benchmark.cu` | `build/benchmark` |

**Example when a file is missing (`make kernel`):**
```
----------------------------------------------------------------
  MISSING: src/kernel/sha256_gpu.cu
  Tasks:   CUDA sha256_kernel, load dataset, write gpu_digests.bin
  Expected output when implemented:
    ./build/sha256_gpu data/ -> gpu_digests.bin
----------------------------------------------------------------
```

**Use when:** you have added your module’s source and want to compile it.

---

### `make all`

Runs all four build targets in sequence: `cpu_reference` → `kernel` → `validate` → `benchmark`.

Stops at the **first** missing source file. When every module exists, it builds all binaries under `build/`.

---

## Run commands

### `make run N=1000`

Runs the **full pipeline** after a successful `make all`:

```bash
./build/cpu_reference 1000 data/
./build/sha256_gpu data/
./build/validate data/
./build/benchmark data/
```

- **`N`** — number of messages (default: `1000`). Example: `make run N=1000000`  
- **`DATA_DIR`** — dataset folder (default: `data`). Example: `make run DATA_DIR=data/test N=500`

**Requires:** all four source files implemented and a machine with CUDA + OpenSSL.

**Expected when complete:**

| Step | Expected result |
|------|-----------------|
| cpu_reference | Creates `data/messages.bin`, `offsets.bin`, `lengths.bin`, `meta.txt`, `expected_digests.bin` |
| kernel | Creates `data/gpu_digests.bin` |
| validate | Prints `ALL MATCH` (or first mismatch details) |
| benchmark | Prints hashes/sec, GB/s, GPU vs CPU timing |

Alternative wrapper:

```bash
./scripts/run_all.sh 1000
```

---

### `make clean`

Deletes the `build/` directory (compiled binaries). Does **not** delete `data/` or `results/`.

---

## Files the Makefile checks

### Source files (you implement)

| File | Task |
|------|------|
| `include/sha256.cuh` | Device SHA-256 helpers |
| `src/kernel/sha256_gpu.cu` | CUDA kernel; writes `gpu_digests.bin` |
| `src/cpu_reference/cpu_reference.cpp` | OpenSSL dataset + CPU reference |
| `src/validate/validate.cpp` | Compare GPU vs CPU digests |
| `src/benchmark/benchmark.cu` | CUDA event timing; hashes/sec; GB/s |
| `include/dataset_io.hpp` | Dataset struct + read/write API |
| `src/common/dataset_io.cpp` | Optional shared `.bin` I/O implementation |

### Data files (generated at runtime, in `data/`)

| File | Created by |
|------|------------|
| `messages.bin` | cpu_reference |
| `offsets.bin` | cpu_reference |
| `lengths.bin` | cpu_reference |
| `meta.txt` | cpu_reference |
| `expected_digests.bin` | cpu_reference |
| `gpu_digests.bin` | kernel |

These are gitignored — they are produced when you run the pipeline, not committed.

---

## Typical workflow

```
Day 1   make status          # see what is missing
        make pipeline        # understand the order

Day 2   Each member adds their source file, then:
        make <their-target>  # e.g. make validate

        When all modules exist:
        make all
        make run N=1000

Day 3   make run N=1000000   # large-scale on GPU machine
        make clean           # optional cleanup
```

---

## Module labels

The Makefile shows **tasks only**. Module labels (M1, M2, M4, M5) and the team roster are in [TASKS.md](../TASKS.md) and [IO_CONTRACT.md](../IO_CONTRACT.md).

---

## Related docs

- [IO_CONTRACT.md](../IO_CONTRACT.md) — data formats and kernel contract  
- [TASKS.md](../TASKS.md) — team tasks and timeline  
- [SHA256_GPU_OVERVIEW.md](SHA256_GPU_OVERVIEW.md) — SHA-256 and CPU vs GPU background  
- [README.md](../README.md) — project overview and Colab setup
