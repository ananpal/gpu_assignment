// =====================================================================
// sha256_gpu.cu — scaled GPU SHA-256 (Member 3 / Anand)
//
// Loads a dataset produced by the CPU reference (Karan's cpu_reference /
// generate_dataset.py) in the I/O-contract §4 format, hashes every message
// on the GPU (one thread per message), and writes data/gpu_digests.bin.
// If data/expected_digests.bin exists, it also reports a match summary.
//
// Built for SCALE (millions of messages):
//   - size_t for all byte-size / index math (no int overflow)
//   - CUDA_CHECK on every CUDA call (fail loudly, not silently)
//   - summary output only (no per-message printing)
//
// Build: nvcc src/kernel/sha256_gpu.cu -o sha256_gpu
// Run:   ./sha256_gpu [data_dir]        (default data_dir = "data")
// =====================================================================
#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdlib>
#include <cstdint>

#include "../../include/sha256.cuh"

// Abort with a clear message if any CUDA call fails.
#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _err = (call);                                            \
        if (_err != cudaSuccess) {                                            \
            std::cerr << "CUDA error: " << cudaGetErrorString(_err)           \
                      << " at " << __FILE__ << ":" << __LINE__ << "\n";       \
            std::exit(1);                                                     \
        }                                                                     \
    } while (0)

// Read an entire binary file into a byte vector.
static std::vector<unsigned char> read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) { std::cerr << "cannot open " << path << "\n"; std::exit(1); }
    std::streamsize n = f.tellg();
    f.seekg(0);
    std::vector<unsigned char> buf(n > 0 ? (size_t)n : 0);
    if (n > 0) f.read(reinterpret_cast<char*>(buf.data()), n);
    return buf;
}

// Parse "num_messages=<N>" from meta.txt.
static int read_num_messages(const std::string& path) {
    std::ifstream f(path);
    if (!f) { std::cerr << "cannot open " << path << "\n"; std::exit(1); }
    std::string line;
    std::getline(f, line);
    auto pos = line.find('=');
    if (pos == std::string::npos) { std::cerr << "bad meta.txt: " << line << "\n"; std::exit(1); }
    return std::stoi(line.substr(pos + 1));
}

int main(int argc, char** argv) {
    const std::string dir = (argc > 1) ? argv[1] : "data";

    // ---- Load the dataset (I/O contract §4). Assumes little-endian int32
    //      on disk, matching the generator and x86 hosts. ----
    int num_messages = read_num_messages(dir + "/meta.txt");
    std::vector<unsigned char> h_messages = read_file(dir + "/messages.bin");
    std::vector<unsigned char> off_raw    = read_file(dir + "/offsets.bin");
    std::vector<unsigned char> len_raw    = read_file(dir + "/lengths.bin");

    if (off_raw.size() != (size_t)num_messages * sizeof(int) ||
        len_raw.size() != (size_t)num_messages * sizeof(int)) {
        std::cerr << "offsets/lengths size does not match num_messages\n";
        return 1;
    }
    const int* h_offsets = reinterpret_cast<const int*>(off_raw.data());
    const int* h_lengths = reinterpret_cast<const int*>(len_raw.data());

    const size_t total_bytes  = h_messages.size();
    const size_t digest_bytes = (size_t)num_messages * 32;

    // ---- Device memory (size_t sizes; every call checked). ----
    unsigned char *d_messages = nullptr, *d_digests = nullptr;
    int *d_offsets = nullptr, *d_lengths = nullptr;
    CUDA_CHECK(cudaMalloc(&d_messages, total_bytes));
    CUDA_CHECK(cudaMalloc(&d_offsets,  (size_t)num_messages * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_lengths,  (size_t)num_messages * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_digests,  digest_bytes));

    CUDA_CHECK(cudaMemcpy(d_messages, h_messages.data(), total_bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets,  h_offsets, (size_t)num_messages * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_lengths,  h_lengths, (size_t)num_messages * sizeof(int), cudaMemcpyHostToDevice));

    // ---- Launch: one thread per message. ----
    int threadsPerBlock = 256;
    int numBlocks = (int)(((size_t)num_messages + threadsPerBlock - 1) / threadsPerBlock);
    sha256_kernel<<<numBlocks, threadsPerBlock>>>(d_messages, d_offsets, d_lengths,
                                                  d_digests, num_messages);
    CUDA_CHECK(cudaGetLastError());        // catch launch errors
    CUDA_CHECK(cudaDeviceSynchronize());   // catch execution errors

    // ---- Copy digests back and persist them. ----
    std::vector<unsigned char> h_digests(digest_bytes);
    CUDA_CHECK(cudaMemcpy(h_digests.data(), d_digests, digest_bytes, cudaMemcpyDeviceToHost));

    {
        std::ofstream out(dir + "/gpu_digests.bin", std::ios::binary);
        out.write(reinterpret_cast<const char*>(h_digests.data()), digest_bytes);
    }

    std::cout << "Hashed " << num_messages << " messages (" << total_bytes
              << " bytes) -> " << dir << "/gpu_digests.bin\n";

    // ---- Optional: compare against the CPU reference if present. ----
    std::ifstream exp_probe(dir + "/expected_digests.bin", std::ios::binary);
    if (exp_probe) {
        exp_probe.close();
        std::vector<unsigned char> expected = read_file(dir + "/expected_digests.bin");
        if (expected.size() != digest_bytes) {
            std::cout << "expected_digests.bin size mismatch; skipping verify\n";
        } else {
            size_t mismatches = 0;
            long long first = -1;
            for (size_t k = 0; k < (size_t)num_messages; k++) {
                if (memcmp(h_digests.data() + k * 32, expected.data() + k * 32, 32) != 0) {
                    mismatches++;
                    if (first < 0) first = (long long)k;
                }
            }
            if (mismatches == 0)
                std::cout << "VALIDATION: ALL MATCH (" << num_messages << " messages)\n";
            else
                std::cout << "VALIDATION: " << mismatches << " mismatch(es); first at index "
                          << first << "\n";
        }
    }

    cudaFree(d_messages); cudaFree(d_offsets); cudaFree(d_lengths); cudaFree(d_digests);
    return 0;
}
