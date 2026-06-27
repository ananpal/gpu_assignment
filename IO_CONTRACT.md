# I/O Contract — GPU SHA-256

**Owner:** Anand
**Rule:** this is the single source of truth for data formats. Change it here first, then update your code — never the other way around.

---

## 1. Decisions (locked)

| Decision | Choice |
|---|---|
| Algorithm | SHA-256 (NIST FIPS 180-4) |
| Output per message | 32 bytes (256 bits), always |
| Parallelization | One GPU thread per message |
| Language | CUDA C/C++, compiled with `nvcc` |
| CPU reference | OpenSSL `SHA256()` (C++) |
| Digest byte order | Big-endian (standard SHA-256) |

---

## 2. Data formats

### Input to the kernel

All messages packed back-to-back in one byte buffer, plus two index arrays:

| Name | Type | Meaning |
|---|---|---|
| `messages` | `unsigned char*` | All messages concatenated, no separators |
| `offsets` | `int*` | `offsets[i]` = byte index where message `i` starts |
| `lengths` | `int*` | `lengths[i]` = byte length of message `i` |
| `num_messages` | `int` | Total message count |

Example — three messages `"abc"`, `"hello"`, `"hi"`:
```
messages = abchellohi     (10 bytes, no gaps)
offsets  = [0, 3, 8]
lengths  = [3, 5, 2]
```

Rule: messages are tightly packed — `offsets[0] = 0`, `offsets[i] + lengths[i] = offsets[i+1]`.

### Output from the kernel

| Name | Type | Meaning |
|---|---|---|
| `digests` | `unsigned char*` | `num_messages * 32` bytes |

Digest for message `i` is at `digests[i*32 .. i*32+31]`. Raw bytes, not hex. Hex conversion happens on the CPU only.

### Core rule

> **Thread `i` reads `messages[offsets[i] .. offsets[i]+lengths[i]]` and writes 32 bytes to `digests[i*32]`.**

---

## 3. Function signatures

### GPU kernel (src/kernel/sha256_gpu.cu)
```c
__global__ void sha256_kernel(
    const unsigned char* messages,
    const int*           offsets,
    const int*           lengths,
    unsigned char*       digests,
    int                  num_messages);
```

### Host API (include/sha256_gpu.hpp)
```cpp
std::vector<unsigned char> sha256_gpu_hash(
    const unsigned char* messages, std::size_t total_bytes,
    const int* offsets, const int* lengths, int num_messages);
```

### CPU reference (src/cpu_reference/cpu_reference.cpp)
```cpp
// One message; returns 32 raw bytes.
std::vector<unsigned char> cpu_sha256(const unsigned char* data, size_t len) {
    std::vector<unsigned char> out(32);
    SHA256(data, len, out.data());   // OpenSSL
    return out;
}
```

---

## 4. Dataset files on disk

Karan's generator writes these; the kernel, validator, and benchmark read them.

| File | Contents |
|---|---|
| `messages.bin` | Packed messages buffer |
| `offsets.bin` | `num_messages` × int32, little-endian |
| `lengths.bin` | `num_messages` × int32, little-endian |
| `meta.txt` | `num_messages=<N>` |
| `expected_digests.bin` | CPU reference output: `N × 32` bytes |
| `gpu_digests.bin` | GPU output written by `hash_dataset` |

---

## 5. Test vectors (check these first — always)

| Input | SHA-256 (hex) |
|---|---|
| `""` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `"abc"` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
| `"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"` | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |

If these don't match, stop and fix padding/endianness before anything else.

---

## 6. Edge cases (everyone must handle)

1. **Empty message** (`length == 0`) — valid; SHA-256 padding handles it. Do not special-case.
2. **Out-of-range threads** — guard with `if (i < num_messages)` in the kernel.
3. **Raw bytes only** — digests are raw bytes, not hex. Convert to hex on the CPU only.
4. **Null bytes in messages** — never use `strlen`; always use `lengths[i]`.
5. **Endianness** — SHA-256 is big-endian internally and on output. This is the #1 bug source.

---

## 7. Launch configuration

```cpp
int threadsPerBlock = 256;
int numBlocks = (num_messages + threadsPerBlock - 1) / threadsPerBlock;
sha256_kernel<<<numBlocks, threadsPerBlock>>>(
    d_messages, d_offsets, d_lengths, d_digests, num_messages);
```

The benchmark may vary `threadsPerBlock` (128/256/512) — that does not change the contract.
