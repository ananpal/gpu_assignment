# Team Task Plan — GPU SHA-256 (C++ / CUDA)

**Group:** Group 29

**Deadline:** Sunday afternoon. **Today:** Friday.
**Core language:** C++ (CUDA is C++; CPU reference uses OpenSSL in C++).
**Working window:** Fri afternoon → Sat (full day) → Sun morning → Sun afternoon = submit.

## Team

| Name | Roll No. | Role | Owns |
|------|----------|------|------|
| **Anand Pal** | G25AIT1019 | I/O contract + CUDA kernel | `IO_CONTRACT.md`, `sha256_gpu.cu` |
| **Arundhati** | G25AIT1033 | Correctness validation tool | `validate.cpp` |
| **Mohshinsha Harunsha Shahmadar** | G25AIT1093 | Benchmark harness + build system + report | `benchmark.cu`, `Makefile` |
| **Mudrik Kaushik** | G25AIT1096 | Repo setup + large-scale GPU runs | GitHub repo, `results/` |
| **Karan Kapoor** | G25AIT1233 | CPU reference & dataset generator | `cpu_reference.cpp` |

---

## The key workflow: develop small (Colab) → run big (Mudrik's machine)

Only Mudrik has the GPU machine. So **everyone develops and tests on Colab with a
SMALL dataset** (1K–10K messages), and once it works, **Mudrik runs the big jobs**
(1M–10M messages) on his machine for the final correctness check and benchmarks.

```
   Anand (kernel) ┐
   Karan (data)   ├─ develop + test on COLAB, small data, push to Git
   Arundhati(val) ┘            │
                               ▼  (Saturday evening: everything works small)
              Mudrik pulls from Git, runs BIG on his GPU machine:
                 - final correctness validation (1M–10M messages)
                 - official benchmarks + scaling curves + GPU specs
```

**Consequence:** Mudrik is *downstream* — his runs are only meaningful once the
kernel, validator, and dataset all work. So the **Saturday-evening milestone**
(everything passes on small data) is the whole game. Miss it and Mudrik has nothing
to scale on Sunday.

**Code travels via Git only.** Mudrik must be able to `git pull && make && ./run`.
No emailing files around.

---

## Anand Pal (G25AIT1019) — I/O contract + CUDA kernel
**Owns:** `IO_CONTRACT.md`, `sha256_gpu.cu`

**What to do**
1. **Finalize `IO_CONTRACT.md`** and walk the team through it Friday. Lock the data
   formats and function signatures — this is what lets the other four work in parallel.
2. Build `sha256_gpu.cu` (start from `sha256_multi.cu`): replace the 4 hardcoded
   messages with code that **loads Karan's `.bin` dataset**, runs the kernel, and writes
   `gpu_digests.bin` (same layout as `expected_digests.bin`).
3. Keep the SHA-256 math (`transform`/`hash`) unchanged — it's verified.
4. Stretch (Sun): confirm constants are in `__constant__`, try block sizes 128/256/512.

**How to complete / tips**
- The kernel barely changes; your real work is the host-side `.bin` load/save plumbing
  (`std::ifstream` in binary mode).
- Test on Colab with a small dataset until it prints `ALL PASS`, then push for Mudrik.
- **Done when:** loads Karan's dataset, runs the kernel, writes `gpu_digests.bin`, passes on small data.

---

## Karan Kapoor (G25AIT1233) — CPU reference & dataset generator (C++ / OpenSSL)
**Owns:** `cpu_reference.cpp`

**What to do**
1. Write a C++ program using **OpenSSL** (`#include <openssl/sha.h>`, `SHA256(...)`) that:
   - Generates N synthetic messages (varying lengths).
   - Computes each digest with OpenSSL (the trusted CPU baseline).
   - Writes the I/O-contract §4 files: `messages.bin`, `offsets.bin`, `lengths.bin`,
     `expected_digests.bin`, `meta.txt`.
2. Embed the **NIST test vectors** (`""`, `"abc"`, the 56-byte string) at the front and
   assert OpenSSL matches their published hashes (your correctness gate).
3. Make N a command-line argument (1K / 100K / 1M / 10M) for Mudrik's scaling runs.

**How to complete / tips**
- Colab: `!apt-get install -y libssl-dev`, then `g++ cpu_reference.cpp -o cpu_reference -lssl -lcrypto`.
- `generate_dataset.py` already shows the exact logic + file layout — **port it to C++**, keep the format identical.
- You're upstream of everyone — get a small dataset out **Saturday morning** so Anand/Arundhati can work.
- **Done when:** produces the 5 files, NIST asserts pass, byte counts match the contract.

---

## Arundhati (G25AIT1033) — Correctness validation
**Owns:** `validate.cpp`

**What to do**
1. Write a C++ tool that reads `gpu_digests.bin` (Anand) and `expected_digests.bin`
   (Karan) and compares them **slot by slot** (32 bytes each, `memcmp`).
2. Report: total messages, number matching, and the **first mismatch** (index + both hex
   digests) so Anand can debug. Print `ALL MATCH` / `N MISMATCHES`.
3. Build an **edge-case suite**: empty string, 1 byte, exactly 55 / 56 / 64 bytes
   (block-boundary cases), a multi-block message. These catch padding/endian bugs.
4. Own the "is it correct?" answer for the report.

**How to complete / tips**
- Fully independent C++ — build and test against Karan's files before Anand's kernel is even done.
- The 55/56/64-byte lengths are exactly where SHA padding bugs hide — make those explicit tests.
- Your tool is what Mudrik runs at scale, so make it work on small data first.
- **Done when:** reports `ALL MATCH` on a small dataset and your edge-case suite passes.

---

## Mohshinsha Harunsha Shahmadar (G25AIT1093) — Benchmark harness + build system + report
**Owns:** `benchmark.cu`, `Makefile`, report assembly

**What to do**
1. Write `benchmark.cu`: wrap the kernel launch in **CUDA event timers** to measure pure
   GPU compute. Report **hashes/sec** and **GB/s**, with and without host↔device transfer
   (report both). Also time the **CPU baseline** (Karan's OpenSSL, single-threaded).
2. Write a **`Makefile`** so anyone builds everything with `make` (nvcc for `.cu`,
   `g++ -lssl -lcrypto` for OpenSSL code).
3. Assemble the **report**: collect each member's section, write the intro + security note.

**How to complete / tips**
- CUDA events: `cudaEventCreate/Record/Synchronize/ElapsedTime` around the launch. **Warm up**
  with one throwaway run before timing.
- You write the harness; **Mudrik runs it at scale** and gives you the numbers/charts.
- Start the Makefile Friday so everyone can `make` from day one.
- **Done when:** `benchmark.cu` runs and times GPU vs CPU; `make` builds the whole project.

---

## Mudrik Kaushik (G25AIT1096) — Repo setup + large-scale runs on the GPU machine
**Owns:** the GitHub repo + folder skeleton, and the final results (correctness at scale + benchmarks)

**What to do — Part A: repo setup (FRIDAY, first thing — unblocks everyone)**
> Repo + modular folder skeleton already exist at `ananpal/gpu_assignment` (per `REPO_STRUCTURE.md`).
1. Make sure everyone has access (repo is public; or add all 5 as collaborators).
2. Confirm the `.gitignore` excludes `data/*.bin`, binaries, `build/`.
3. Tell everyone their folder under `src/` so they can clone and start pushing.

**What to do — Part B: large-scale runs (SAT evening → SUN)**
1. Set up the machine once: confirm `nvidia-smi` + `nvcc --version`, install `libssl-dev`,
   `git clone` the repo.
2. Once the others' code works on small data (Sat evening), **run the full pipeline big**:
   - Karan's generator → 1M then 10M dataset.
   - Anand's kernel → `gpu_digests.bin`.
   - Arundhati's `validate.cpp` → confirm **ALL MATCH** at scale.
   - Mohshinsha's `benchmark.cu` → GPU-vs-CPU across sizes (1K→10M).
3. Produce the **headline numbers**: hashes/sec, GB/s, the **scaling curve**, and the exact
   GPU model/specs from `nvidia-smi` for the report.

**How to complete / tips**
- You're downstream — your big runs need everyone else *done*. Push them to finish small by Sat night.
- Run each benchmark a few times and report the median; note transfer-time-included vs not.
- The headline result is the **speedup-vs-size curve** — that's the project's main finding.
- **Done when:** ALL MATCH on 10M messages + a benchmark table/chart of GPU vs CPU across sizes.

---

## All — Report & security note
Each member writes the section for their own piece; Mohshinsha stitches it together:
- Algorithm overview (SHA-256) + parallel design (one thread per message).
- Correctness results (Arundhati/Mudrik) + benchmark results & charts (Mohshinsha/Mudrik).
- **Security note:** GPUs make brute-forcing *fast* hashes cheap, which is why real password
  storage uses *slow, memory-hard* hashes (Argon2/bcrypt). Note where GPU crypto is useful
  (bulk hashing, integrity, mining) vs. a risk.

---

## Timeline

The day-by-day schedule lives in [docs/DAYWISE_PLAN.md](docs/DAYWISE_PLAN.md)
(a temporary working file, removed before submission).

---

## Rules that keep everyone unblocked
1. **Friday: lock the I/O contract first** (Anand). It's what lets everyone parallelize.
2. **Correctness before speed** — no optimization until validation says ALL MATCH.
3. **Test NIST vectors + edge lengths (55/56/64) early** — that's where bugs hide.
4. **Everything via Git** so Mudrik can pull and run big. No emailing files.
5. **Saturday-evening milestone is the whole game:** all code works on small data, so Mudrik can scale Sunday.
