// =====================================================================
// sha256_gpu.hpp — host-callable GPU SHA-256 batch API.
//
// This is a PLAIN C++ header (no CUDA syntax), so any tool — the validator,
// the benchmark — can include it and call the GPU without needing to know
// anything about kernels. The implementation lives in src/kernel/sha256_gpu.cu.
//
// Usage from another tool (e.g. the validator):
//     #include "sha256_gpu.hpp"
//     std::vector<unsigned char> digests =
//         sha256_gpu_hash(messages, total_bytes, offsets, lengths, n);
//     // build: nvcc your_tool.cpp src/kernel/sha256_gpu.cu -o your_tool
// =====================================================================
#pragma once

#include <vector>
#include <cstddef>

// Hash `num_messages` messages on the GPU (one thread per message), following
// the I/O contract: `messages` is the packed byte buffer (length `total_bytes`),
// and offsets[i] / lengths[i] locate message i within it.
//
// Returns a buffer of num_messages * 32 bytes; the digest for message i is at
// bytes [i*32 .. i*32+31]. Aborts the process if any CUDA call fails.
std::vector<unsigned char> sha256_gpu_hash(
    const unsigned char* messages, std::size_t total_bytes,
    const int* offsets, const int* lengths, int num_messages);
