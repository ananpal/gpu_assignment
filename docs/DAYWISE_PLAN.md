# Day-wise Plan (temporary — remove before submission)

> Scratch scheduling for the weekend. This is a working aid, **not** part of the
> deliverable — delete it before final submission. Durable info (roles, ownership,
> rules) stays in [../TASKS.md](../TASKS.md).

**Deadline:** Sunday afternoon. **Today:** Friday.
**Window:** Fri afternoon → Sat (full day) → Sun morning → Sun afternoon = submit.

---

## Friday (today) — setup & unblock
- **Mudrik (FIRST):** confirm the repo + modular folder skeleton, add everyone as
  collaborator (or keep public), confirm the `.gitignore`. Share the URL. *Unblocks all pushes.*
- **Anand:** lead 15-min sync, lock `IO_CONTRACT.md`, get `sha256_multi.cu` printing `ALL PASS`.
- **Mohshinsha:** start the `Makefile`; everyone runs `colab_starter.ipynb` → `SETUP OK`.
- **Mudrik:** set up the GPU machine (driver, nvcc, libssl-dev, clone repo).
- **Karan:** start porting the generator to C++/OpenSSL.
- ✅ End of Friday: repo live, contract agreed, everyone's GPU compiles, Anand's base passes.

## Saturday — build it (the big day)
- **Karan:** finish C++ generator → small dataset out by morning, then a 1M set.
- **Anand:** kernel loads Karan's dataset, writes `gpu_digests.bin` (test small).
- **Arundhati:** `validate.cpp` working + edge-case suite, run against Anand+Karan output.
- **Mohshinsha:** `benchmark.cu` timing on small data; `make` builds everything.
- 🎯 **End of Saturday (the milestone):** validator reports **ALL MATCH** on small data, all code pushed to Git.

## Sunday morning — scale up & benchmark (Mudrik's turn)
- **Mudrik:** pull latest, run 1M then 10M — confirm ALL MATCH at scale, run benchmarks, make charts.
- **Anand:** light kernel optimization if time (block size, constant memory).
- **Arundhati:** lock the correctness claim; **Karan:** generate any extra dataset sizes Mudrik needs.

## Sunday afternoon — integrate & submit
- **Mohshinsha:** assemble report + final results; **all:** write your section. **Submit.**
