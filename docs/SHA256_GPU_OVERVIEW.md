# SHA-256 Hashing on CPU vs GPU — Group 29 Overview

## What is SHA-256 hashing?

**SHA-256** (Secure Hash Algorithm, 256-bit output) is a one-way cryptographic hash function. It takes input data of **any length** and produces a fixed **32-byte (256-bit) digest** — a fingerprint of that data.

Properties that matter:

| Property | Meaning |
|----------|---------|
| **Deterministic** | Same input always gives the same digest |
| **One-way** | Easy to compute hash from data; infeasible to recover data from hash |
| **Avalanche effect** | Tiny input change → completely different digest |
| **Fixed output** | Always 32 bytes, whether input is 0 bytes or 1 GB |

SHA-256 is **not encryption**. You cannot “decrypt” a hash to get the original message. It is used for integrity checks, digital signatures, blockchain, and password verification (with extra techniques).

---

## What does SHA-256 do? (In plain terms)

It runs the input through a structured sequence of bit operations — padding, splitting into 512-bit blocks, and 64 rounds of mixing per block — until a single 256-bit result remains.

```
"hello"  ──►  SHA-256  ──►  2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
(any data)     (algorithm)      (always 32 bytes / 64 hex characters)
```

---

## Real-world examples (2–3)

### 1. File integrity verification

When you download Ubuntu or a large software installer, the website publishes a SHA-256 checksum. After download, you hash the file locally and compare:

```
Expected:  a1b2c3...  (published on website)
Computed:  a1b2c3...  (your machine)
```

If they match, the file was not corrupted or tampered with in transit.

### 2. Git commit IDs

Every Git commit is identified by a SHA-1 hash (similar family of hash). Git stores the snapshot of your project and hashes it to produce a unique commit ID like `7f3a9c2`. If one byte of history changes, the commit hash changes entirely.

### 3. Blockchain / Bitcoin mining

Bitcoin blocks contain thousands of transactions. Miners repeatedly hash block headers with different nonces searching for a hash below a target difficulty. Mining is essentially **massive parallel SHA-256 (double SHA-256) computation** — which is why GPUs and ASICs dominate this workload.

---

## How SHA-256 works on CPU

On CPU, hashing is typically **sequential within a single message**:

```
Message bytes
    │
    ▼
┌─────────────┐
│   Padding   │  Append 1-bit, zeros, and 64-bit length (FIPS 180-4)
└─────────────┘
    │
    ▼
┌─────────────┐
│ Split into  │  512-bit (64-byte) blocks
│   blocks    │
└─────────────┘
    │
    ▼
┌─────────────┐
│ 64 rounds   │  Per block: rotate, XOR, add with constants K[]
│ per block   │  Update internal state (8 × 32-bit words)
└─────────────┘
    │
    ▼
┌─────────────┐
│ Final digest│  32 bytes, big-endian
└─────────────┘
```

### Typical CPU implementation (our project baseline)

We use **OpenSSL** in C++ as the trusted CPU reference:

```cpp
#include <openssl/sha.h>

unsigned char digest[32];
SHA256(message_bytes, message_length, digest);
```

For **many messages**, CPU code usually looks like:

```cpp
for (int i = 0; i < num_messages; i++) {
    SHA256(&messages[offsets[i]], lengths[i], &digests[i * 32]);
}
```

One message at a time. Message 2 waits until message 1 finishes.

---

## Problems with doing this on CPU only

| Issue | Why it hurts |
|-------|--------------|
| **Sequential per message** | Each hash depends only on its own input, but a single CPU core processes messages one after another |
| **Limited cores** | A laptop might have 8–16 threads; a dataset of 10 million messages still takes noticeable time |
| **Underutilized hardware** | Modern CPUs are fast per hash, but they cannot match thousands of lightweight parallel workers |
| **Scale** | Security research, bulk integrity scans, and benchmark datasets (millions of hashes) become slow |
| **Mining / brute-force** | Trying billions of password guesses or nonces on CPU alone is impractical at scale |

Important nuance: **one SHA-256 hash cannot be easily split across CPU cores** because of Merkle–Damgård chaining within a single message. The parallelism is across **independent messages**, not inside one message.

---

## Motivation for using GPU

GPUs are built for **massive parallelism** — thousands of small, independent tasks running at once.

SHA-256 per message is:

- A fixed pattern of arithmetic and bitwise ops (good for GPU ALUs)
- **Independent** across different messages (no data dependency between message A and message B)
- Repeated millions of times in our assignment dataset

So instead of asking one CPU core to hash 10 million messages serially, we ask the GPU to hash **many messages simultaneously**.

---

## What problems does GPU solve for SHA-256?

| CPU limitation | GPU answer |
|----------------|------------|
| Few cores (8–16) | Thousands of CUDA threads (e.g. 256 threads/block × many blocks) |
| Serial loop over messages | One thread per message — all run in parallel |
| Slow bulk throughput | High aggregate hashes/sec on large batches |
| Expensive scaling on CPU | Add GPU compute; amortize launch cost over large N |

What GPU does **not** magically fix:

- A **single** short message is not much faster on GPU (launch + memory transfer overhead)
- Incorrect SHA-256 implementation is still incorrect — speed without correctness is worthless
- Host ↔ device memory copy adds latency (we measure this separately in benchmarks)

---

## Our approach: breaking the problem for GPU parallelization

### What we have on CPU

1. **Dataset generator** (Karan) — creates N messages + `expected_digests.bin` via OpenSSL
2. **Packed layout** — all messages in one buffer with `offsets[]` and `lengths[]`
3. **Validator** (Arundhati) — compares GPU output to CPU reference byte-by-byte

### What we do on GPU

We use the **embarrassingly parallel** model from [IO_CONTRACT.md](../IO_CONTRACT.md):

> **Thread `i` reads message `i` and writes digest `i`.**

```
CPU side                          GPU side
─────────                         ────────
messages.bin  ──copy──►  d_messages
offsets.bin   ──copy──►  d_offsets
lengths.bin   ──copy──►  d_lengths
                              │
                              ▼
                    ┌─────────────────────┐
                    │  sha256_kernel      │
                    │                     │
                    │  thread 0 → hash 0  │
                    │  thread 1 → hash 1  │
                    │  thread 2 → hash 2  │
                    │  ...                │
                    │  thread N-1 → N-1   │
                    └─────────────────────┘
                              │
                              ▼
gpu_digests.bin  ◄──copy──  d_digests
```

### How we break the problem

| Piece | Where | Parallel? |
|-------|-------|-----------|
| Padding + 64 rounds for **one** message | Inside `sha256_hash()` on one thread | No — inherent to SHA-256 |
| Hashing **message 0, 1, 2, … N-1** | Different threads | **Yes — this is our GPU win** |

We do **not** try to parallelize the 64 rounds inside one hash (hard, limited benefit). We parallelize **across messages**.

### Launch configuration

```c
int threadsPerBlock = 256;
int numBlocks = (num_messages + threadsPerBlock - 1) / threadsPerBlock;
sha256_kernel<<<numBlocks, threadsPerBlock>>>(...);
```

Example: 1,000,000 messages → ~3,907 blocks × 256 threads → up to 1M workers hashing in parallel (threads beyond N exit early).

---

## Why can we say it will be faster?

For **large N independent messages**, GPU throughput wins because:

1. **Occupancy** — thousands of threads hide latency; CPU runs a tight serial loop
2. **Throughput-oriented design** — GPUs optimize for FLOPs/ops per second across many lanes, not single-thread latency
3. **Amortized overhead** — kernel launch and PCIe transfer cost matter less as N grows (1M+ messages)
4. **Same work per hash** — each thread does identical SHA-256 logic; perfect for SIMD/SIMT execution

Expected shape of results (typical, not guaranteed):

```
Messages     CPU time        GPU time       Notes
────────     ────────        ────────       ─────
1K           fast            maybe slower   launch + transfer dominate
100K         moderate        competitive    GPU starts to pay off
1M–10M       slow on CPU     much faster    parallelism fully utilized
```

We report **hashes/sec** and **GB/s** in benchmarks and compare with/without data transfer to show where time is spent.

---

## Summary

| Question | Answer |
|----------|--------|
| What is SHA-256? | One-way 256-bit fingerprint of arbitrary data |
| CPU approach? | OpenSSL `SHA256()` in a loop, one message at a time |
| CPU problem? | Serial across messages; limited cores at large scale |
| Why GPU? | Thousands of parallel threads for independent hashes |
| Our trick? | **One GPU thread = one message** — not parallel inside one hash |
| Why faster? | Aggregate throughput on large batches beats serial CPU loops |

**Golden rule for Group 29:** correctness before speed. Prove `""` and `"abc"` NIST vectors first, then scale to millions of messages.

---

## References

- [IO_CONTRACT.md](../IO_CONTRACT.md) — data formats and kernel contract
- [TASKS.md](../TASKS.md) — team deliverables and timeline
- NIST FIPS 180-4 — SHA-256 specification
