# I/O Contract — GPU SHA-256 Project

**Group:** Group 29
**Owner:** M1 — Algorithm & Spec (see [TASKS.md](TASKS.md) for roster)
**Status:** Day-1 deliverable. This is the single source of truth. If a format
needs to change, change it HERE first, then tell the team — do not change it
silently in your own code.

---

## 0. Module mapping

| Module | Responsibility |
|--------|----------------|
| M1 | I/O contract + CUDA SHA-256 kernel |
| M2 | CPU reference (OpenSSL) + dataset generator |
| M4 | Correctness validation |
| M5 | Benchmark harness + Makefile |
| — | Repo setup + large-scale GPU runs (`results/`) |

> Team roster (names and roll numbers): [TASKS.md](TASKS.md).

---

## 1. Project decisions (locked)

| Decision | Choice |
|---|---|
| Algorithm | **SHA-256** (NIST FIPS 180-4) |
| Output size | **32 bytes (256 bits)** per message — always |
| Parallelization model | **One GPU thread hashes one message** |
| Language / platform | **CUDA C/C++**, compiled with `nvcc` |
| Reference platform | **C++ OpenSSL** (`SHA256()` from `<openssl/sha.h>`) on CPU |
| Byte order of digest | **Big-endian** (standard SHA-256 output order) |
| GPU output file | **`gpu_digests.bin`** (same 32-byte-per-slot layout as `expected_digests.bin`) |

> We hash **many independent messages**, not one giant file. Each message is
> small (a few bytes to a few KB). This is the "embarrassingly parallel" case.

> **Colab note:** `colab_starter.ipynb` uses Python `hashlib` only to sanity-check
> the GPU environment. The **submission pipeline** uses OpenSSL C++ as the trusted
> CPU baseline (see §3.3).

---

## 2. The data formats (the actual contract)

All five members code against exactly these structures.

### 2.1 INPUT to the kernel

The CPU packs all messages into **one big byte buffer**, plus two index arrays.

| Name | Type | Meaning |
|---|---|---|
| `messages` | `unsigned char*` | All messages concatenated back-to-back, no separators |
| `offsets` | `int*` (or `size_t*`) | `offsets[i]` = byte index in `messages` where message `i` starts |
| `lengths` | `int*` | `lengths[i]` = byte length of message `i` |
| `num_messages` | `int` | Total number of messages |

**Example.** Three messages: `"abc"`, `"hello"`, `"hi"`.

```
messages =  a b c h e l l o h i        (10 bytes total, no gaps)
index:      0 1 2 3 4 5 6 7 8 9

offsets  = [0, 3, 8]      // "abc" starts at 0, "hello" at 3, "hi" at 8
lengths  = [3, 5, 2]      // lengths in bytes
num_messages = 3
```

> Rule: `offsets[i] + lengths[i] == offsets[i+1]` for all i (messages are tightly packed).
> `offsets[0]` is always `0`. Total buffer size = `offsets[last] + lengths[last]`.

### 2.2 OUTPUT from the kernel

| Name | Type | Meaning |
|---|---|---|
| `digests` | `unsigned char*` | Output buffer, size = `num_messages * 32` bytes |

- The digest for message `i` lives at bytes **`digests[i*32]` .. `digests[i*32 + 31]`**.
- Each digest is exactly **32 bytes**, big-endian, raw bytes (NOT hex text).
- Converting to the 64-char hex string is done on the **CPU side** for display/comparison.

```
digests:  [32 bytes for msg 0][32 bytes for msg 1][32 bytes for msg 2]...
          ^i=0                ^i=1                ^i=2
```

### 2.3 THE CORE RULE

> **Thread `i` reads message `i` (using `offsets[i]`, `lengths[i]`) and writes
> its 32-byte digest to `digests[i*32]`.**

This single rule is why everything lines up. M2 generates message `i`, M1's
thread `i` hashes it, M4 compares output slot `i` against M2's reference for
message `i`.

---

## 3. Function signatures (everyone uses these names)

### 3.1 The GPU kernel (M1 implements)

```c
__global__ void sha256_kernel(
    const unsigned char* messages,   // packed input buffer (device memory)
    const int*           offsets,    // start index of each message
    const int*           lengths,    // byte length of each message
    unsigned char*       digests,    // output: num_messages * 32 bytes (device memory)
    int                  num_messages);
```

### 3.2 The device helper (M1 implements)

```c
// Hashes ONE message; writes exactly 32 bytes to `out`.
__device__ void sha256_hash(const unsigned char* msg, int len, unsigned char* out);
```

### 3.3 The CPU reference (M2 implements)

C++ reference using OpenSSL that produces the EXACT same logical output:

```cpp
#include <openssl/sha.h>

// Return the 32-byte big-endian SHA-256 digest of one message.
inline void cpu_sha256(const unsigned char* msg, size_t len, unsigned char out[32]) {
    SHA256(msg, len, out);
}
```

M2 also provides the dataset in the packed format above, so M1/M4/M5 can load it.

---

## 4. Dataset format on disk (M2 produces, M1/M4/M5 consume)

All paths below are relative to a dataset directory (default: `data/`).

M2 writes:

| File | Contents |
|---|---|
| `messages.bin` | The packed `messages` byte buffer |
| `offsets.bin` | `num_messages` 32-bit ints (little-endian on disk) |
| `lengths.bin` | `num_messages` 32-bit ints (little-endian on disk) |
| `meta.txt` | One line: `num_messages=<N>` |
| `expected_digests.bin` | CPU reference output: `N * 32` bytes (for M4 to diff against) |

M1 writes:

| File | Contents |
|---|---|
| `gpu_digests.bin` | GPU kernel output: `N * 32` bytes (same layout as `expected_digests.bin`) |

> Keep `int` = 32-bit signed. If we ever exceed ~2 billion total bytes we switch
> offsets to `size_t` — flag M1 first.

> Shared read/write helpers will live in `include/dataset_io.hpp` (added by module owners).

---

## 5. Mandatory test vectors (M2 provides, M4 checks FIRST)

These are published correct answers. **If these don't match, stop and fix
padding/endianness before testing anything else.**

| Input | Correct SHA-256 (hex) |
|---|---|
| `""` (empty) | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `"abc"` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| `"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"` | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |

(Hex shown for humans; the kernel outputs the raw 32 bytes that hex-encode to this.)

---

## 6. Edge cases everyone must agree on

1. **Empty message** (`length == 0`) is valid → must produce the empty-string digest above. SHA-256 padding handles this; don't special-case it away.
2. **Out-of-range threads:** the kernel is launched with `num_blocks * threads_per_block >= num_messages`, so some threads have `i >= num_messages`. Those threads **must do nothing** (`if (i < num_messages)` guard).
3. **Digest is raw bytes, not hex.** Hex conversion happens on the CPU only.
4. **Message bytes are arbitrary** (can include `0x00`). Never treat messages as C strings / never rely on null terminators — always use `lengths[i]`.
5. **Endianness:** SHA-256 processes message words and outputs the digest in **big-endian**. This is the #1 bug source — M1 must handle it inside `sha256_hash`.

---

## 7. Launch configuration (M1, agreed default)

```c
int threadsPerBlock = 256;
int numBlocks = (num_messages + threadsPerBlock - 1) / threadsPerBlock;
sha256_kernel<<<numBlocks, threadsPerBlock>>>(
    d_messages, d_offsets, d_lengths, d_digests, num_messages);
```

M5 may vary `threadsPerBlock` (128/256/512) during benchmarking — that's fine,
it does not change the contract.

---

## 8. What each member can now start independently

- **M2** — generate dataset in the §4 format + `expected_digests.bin` + test vectors (§5).
- **M1** — implement §3.1 and §3.2 against the §2 layout; write `gpu_digests.bin`.
- **M4** — write a diff tool that loads `gpu_digests.bin` (from M1) and `expected_digests.bin` (from M2) and compares slot `i` for all `i`; report first mismatch.
- **M5** — time the kernel launch (CUDA events) over the dataset; report hashes/sec and GB/s.

If any of these need a format change, it goes through M1 and gets updated in this file.
