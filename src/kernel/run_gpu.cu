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

static std::vector<unsigned char> read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) { std::cerr << "cannot open " << path << "\n"; std::exit(1); }
    std::streamsize n = f.tellg();
    f.seekg(0);
    std::vector<unsigned char> buf(n > 0 ? (size_t)n : 0);
    if (n > 0) f.read(reinterpret_cast<char*>(buf.data()), n);
    return buf;
}

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

    // Load the dataset (assumes little-endian int32 on disk, matching the generator).
    int num_messages = read_num_messages(dir + "/meta.txt");
    std::vector<unsigned char> messages = read_file(dir + "/messages.bin");
    std::vector<unsigned char> off_raw  = read_file(dir + "/offsets.bin");
    std::vector<unsigned char> len_raw  = read_file(dir + "/lengths.bin");

    if (off_raw.size() != (size_t)num_messages * sizeof(int) ||
        len_raw.size() != (size_t)num_messages * sizeof(int)) {
        std::cerr << "offsets/lengths size does not match num_messages\n";
        return 1;
    }
    const int* offsets = reinterpret_cast<const int*>(off_raw.data());
    const int* lengths = reinterpret_cast<const int*>(len_raw.data());

    // Hash everything on the GPU via the shared API.
    std::vector<unsigned char> digests =
        sha256_gpu_hash(messages.data(), messages.size(), offsets, lengths, num_messages);

    // Persist the GPU digests.
    {
        std::ofstream out(dir + "/gpu_digests.bin", std::ios::binary);
        out.write(reinterpret_cast<const char*>(digests.data()), digests.size());
    }
    std::cout << "Hashed " << num_messages << " messages (" << messages.size()
              << " bytes) -> " << dir << "/gpu_digests.bin\n";

    // Optional: verify against the CPU reference if it is present.
    std::ifstream probe(dir + "/expected_digests.bin", std::ios::binary);
    if (probe) {
        probe.close();
        std::vector<unsigned char> expected = read_file(dir + "/expected_digests.bin");
        if (expected.size() != digests.size()) {
            std::cout << "expected_digests.bin size mismatch; skipping verify\n";
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
