// =====================================================================
// sha256_gpu.cu — the GPU SHA-256 ENGINE (Member 3 / Anand).
//
// Implements the host-callable API declared in include/sha256_gpu.hpp:
//   sha256_gpu_hash(messages, total_bytes, offsets, lengths, num_messages)
// runs the full GPU pipeline (alloc -> copy -> launch -> copy back) and
// returns the digests. There is NO main() here, so other tools (the
// validator, the benchmark) can link this object and call the function.
//
// Built for scale: size_t size/index math, CUDA_CHECK on every call.
//
// Link into a tool: nvcc your_tool.cpp src/kernel/sha256_gpu.cu -o your_tool
// Standalone driver: see run_gpu.cu.
// =====================================================================
#include "../../include/sha256_gpu.hpp"
#include "../../include/sha256.cuh"

#include <iostream>
#include <cstdlib>

// Abort with a clear message if any CUDA call fails (no silent wrong answers).
#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _err = (call);                                            \
        if (_err != cudaSuccess) {                                            \
            std::cerr << "CUDA error: " << cudaGetErrorString(_err)           \
                      << " at " << __FILE__ << ":" << __LINE__ << "\n";       \
            std::exit(1);                                                     \
        }                                                                     \
    } while (0)

std::vector<unsigned char> sha256_gpu_hash(
        const unsigned char* messages, std::size_t total_bytes,
        const int* offsets, const int* lengths, int num_messages) {

    const std::size_t digest_bytes = (std::size_t)num_messages * 32;

    unsigned char *d_messages = nullptr, *d_digests = nullptr;
    int *d_offsets = nullptr, *d_lengths = nullptr;

    // cudaMalloc(0) is implementation-defined; guard the all-empty case.
    CUDA_CHECK(cudaMalloc(&d_messages, total_bytes ? total_bytes : 1));
    CUDA_CHECK(cudaMalloc(&d_offsets,  (std::size_t)num_messages * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_lengths,  (std::size_t)num_messages * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_digests,  digest_bytes));

    if (total_bytes)
        CUDA_CHECK(cudaMemcpy(d_messages, messages, total_bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets, offsets, (std::size_t)num_messages * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_lengths, lengths, (std::size_t)num_messages * sizeof(int), cudaMemcpyHostToDevice));

    int threadsPerBlock = 256;
    int numBlocks = (int)(((std::size_t)num_messages + threadsPerBlock - 1) / threadsPerBlock);
    sha256_kernel<<<numBlocks, threadsPerBlock>>>(d_messages, d_offsets, d_lengths,
                                                  d_digests, num_messages);
    CUDA_CHECK(cudaGetLastError());        // launch errors
    CUDA_CHECK(cudaDeviceSynchronize());   // execution errors

    std::vector<unsigned char> digests(digest_bytes);
    CUDA_CHECK(cudaMemcpy(digests.data(), d_digests, digest_bytes, cudaMemcpyDeviceToHost));

    cudaFree(d_messages); cudaFree(d_offsets); cudaFree(d_lengths); cudaFree(d_digests);
    return digests;
}
