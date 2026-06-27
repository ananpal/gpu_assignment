// =====================================================================
// run_gpu.cu — standalone driver for the GPU SHA-256 engine.
//
// Loads a dataset (I/O-contract §4) from a directory, calls the reusable
// sha256_gpu_hash() API, writes data/gpu_digests.bin, and (if present)
// verifies against data/expected_digests.bin with a summary.
//
// Build: nvcc run_gpu.cu sha256_gpu.cu -o sha256_gpu
// Run:   ./sha256_gpu [data_dir]        (default "data")
// =====================================================================
#include "../../include/sha256_gpu.hpp"

#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <cstdlib>
#include <stdexcept>

static std::vector<unsigned char> read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) { std::cerr << "error: cannot open " << path << "\n"; std::exit(1); }
    std::streamsize n = f.tellg();
    f.seekg(0);
    std::vector<unsigned char> buf(n > 0 ? (size_t)n : 0);
    if (n > 0) f.read(reinterpret_cast<char*>(buf.data()), n);
    return buf;
}

static int read_num_messages(const std::string& path) {
    std::ifstream f(path);
    if (!f) { std::cerr << "error: cannot open " << path << "\n"; std::exit(1); }
    std::string line;
    std::getline(f, line);
    auto pos = line.find('=');
    if (pos == std::string::npos) { std::cerr << "error: bad meta.txt: " << line << "\n"; std::exit(1); }
    try {
        return std::stoi(line.substr(pos + 1));
    } catch (const std::exception&) {
        std::cerr << "error: bad num_messages in meta.txt: " << line << "\n";
        std::exit(1);
    }
}

// Every message must lie inside the messages buffer; reject corrupt datasets.
static bool dataset_in_bounds(const int* offsets, const int* lengths, int n, size_t total_bytes) {
    for (int i = 0; i < n; i++) {
        if (offsets[i] < 0 || lengths[i] < 0) return false;
        if ((size_t)offsets[i] + (size_t)lengths[i] > total_bytes) return false;
    }
    return true;
}

int main(int argc, char** argv) {
    const std::string dir = (argc > 1) ? argv[1] : "data";

    // Load the dataset (assumes little-endian int32 on disk, matching the generator).
    int num_messages = read_num_messages(dir + "/meta.txt");
    if (num_messages <= 0) { std::cerr << "error: num_messages must be > 0 (got " << num_messages << ")\n"; return 1; }

    std::vector<unsigned char> messages = read_file(dir + "/messages.bin");
    std::vector<unsigned char> off_raw  = read_file(dir + "/offsets.bin");
    std::vector<unsigned char> len_raw  = read_file(dir + "/lengths.bin");

    if (off_raw.size() != (size_t)num_messages * sizeof(int) ||
        len_raw.size() != (size_t)num_messages * sizeof(int)) {
        std::cerr << "error: offsets/lengths size does not match num_messages\n";
        return 1;
    }
    const int* offsets = reinterpret_cast<const int*>(off_raw.data());
    const int* lengths = reinterpret_cast<const int*>(len_raw.data());

    if (!dataset_in_bounds(offsets, lengths, num_messages, messages.size())) {
        std::cerr << "error: a message offset/length falls outside messages.bin "
                  << "(corrupt or truncated dataset)\n";
        return 1;
    }

    // Hash everything on the GPU via the shared API (may throw on CUDA error).
    std::vector<unsigned char> digests;
    try {
        digests = sha256_gpu_hash(messages.data(), messages.size(), offsets, lengths, num_messages);
    } catch (const std::exception& e) {
        std::cerr << "error: GPU hashing failed: " << e.what() << "\n";
        return 1;
    }

    // Persist the GPU digests, checking the write succeeded.
    {
        std::ofstream out(dir + "/gpu_digests.bin", std::ios::binary);
        out.write(reinterpret_cast<const char*>(digests.data()), digests.size());
        if (!out) { std::cerr << "error: failed to write " << dir << "/gpu_digests.bin\n"; return 1; }
    }
    std::cout << "Hashed " << num_messages << " messages (" << messages.size()
              << " bytes) -> " << dir << "/gpu_digests.bin\n";

    // Optional: verify against the CPU reference if it is present.
    std::ifstream probe(dir + "/expected_digests.bin", std::ios::binary);
    if (probe) {
        probe.close();
        std::vector<unsigned char> expected = read_file(dir + "/expected_digests.bin");
        if (expected.size() != digests.size()) {
            std::cerr << "warning: expected_digests.bin size mismatch; skipping verify\n";
        } else {
            size_t mismatches = 0;
            long long first = -1;
            for (size_t k = 0; k < (size_t)num_messages; k++) {
                if (memcmp(digests.data() + k * 32, expected.data() + k * 32, 32) != 0) {
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
    return 0;
}
