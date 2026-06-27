// =====================================================================
// sha256_smoke_test.cu — quick sanity check: 4 known messages on the GPU
//
// Verifies the kernel produces correct SHA-256 digests for the NIST test
// vectors before any large-scale run. Uses the shared device code from
// sha256.cuh, so any fix there applies here automatically.
//
// Build: nvcc sha256_smoke_test.cu -o sha256_smoke_test
// Run:   ./sha256_smoke_test        (expect ALL PASS)
// =====================================================================
#include "../../include/sha256.cuh"

#include <cstdio>
#include <cstring>
#include <cstdlib>

#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _e = (call);                                              \
        if (_e != cudaSuccess) {                                              \
            fprintf(stderr, "CUDA error: %s at %s:%d\n",                     \
                    cudaGetErrorString(_e), __FILE__, __LINE__);              \
            exit(1);                                                          \
        }                                                                     \
    } while (0)

int main() {
    const char* msgs[] = {
        "",
        "abc",
        "hello",
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    };
    const char* expected[] = {
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    };
    int n = 4;

    int h_offsets[4], h_lengths[4];
    int total = 0;
    for (int i = 0; i < n; i++) {
        h_offsets[i] = total;
        h_lengths[i] = (int)strlen(msgs[i]);
        total += h_lengths[i];
    }

    unsigned char* h_msgs = (unsigned char*)malloc(total ? total : 1);
    for (int i = 0; i < n; i++)
        memcpy(h_msgs + h_offsets[i], msgs[i], h_lengths[i]);
    unsigned char* h_digests = (unsigned char*)malloc(n * 32);

    unsigned char *d_msgs, *d_digests;
    int *d_offsets, *d_lengths;
    CUDA_CHECK(cudaMalloc(&d_msgs,    total ? total : 1));
    CUDA_CHECK(cudaMalloc(&d_offsets, n * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_lengths, n * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_digests, n * 32));

    if (total) CUDA_CHECK(cudaMemcpy(d_msgs, h_msgs, total, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets, h_offsets, n * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_lengths, h_lengths, n * sizeof(int), cudaMemcpyHostToDevice));

    sha256_kernel<<<1, 32>>>(d_msgs, d_offsets, d_lengths, d_digests, n);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());

    CUDA_CHECK(cudaMemcpy(h_digests, d_digests, n * 32, cudaMemcpyDeviceToHost));

    int all_ok = 1;
    for (int i = 0; i < n; i++) {
        char hex[65];
        for (int j = 0; j < 32; j++) sprintf(hex + j*2, "%02x", h_digests[i*32 + j]);
        int ok = (strcmp(hex, expected[i]) == 0);
        if (!ok) all_ok = 0;
        printf("[%s] \"%s\"\n", ok ? "PASS" : "FAIL", msgs[i]);
        if (!ok) { printf("  got: %s\n  exp: %s\n", hex, expected[i]); }
    }
    printf(all_ok ? "ALL PASS\n" : "SOME FAILED\n");

    free(h_msgs); free(h_digests);
    cudaFree(d_msgs); cudaFree(d_offsets); cudaFree(d_lengths); cudaFree(d_digests);
    return all_ok ? 0 : 1;
}
