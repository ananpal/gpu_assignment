#pragma once

// Device SHA-256 — see IO_CONTRACT.md §3.1 and §3.2.
// Anand implements sha256_transform and sha256_hash here.

__device__ void sha256_hash(const unsigned char* msg, int len, unsigned char* out);

__global__ void sha256_kernel(
    const unsigned char* messages,
    const int* offsets,
    const int* lengths,
    unsigned char* digests,
    int num_messages);
