// =====================================================================
// validate.cpp — Correctness validation (Member 4 / Arundhati)
//
// Confirms the GPU SHA-256 output matches a trusted CPU reference (OpenSSL).
// Two parts:
//   1. Edge-case suite — empty, 1 byte, exactly 55/56/64 bytes (block
//      boundaries), and a multi-block message: the spots where padding /
//      endianness bugs hide.
//   2. Dataset check — loads data/, hashes every message on the GPU via the
//      shared API (sha256_gpu_hash), and compares slot-by-slot against the CPU
//      reference (or data/expected_digests.bin if present).
//
// It runs the GPU through the kernel API, not by knowing any CUDA.
//
// Build: nvcc validate.cpp ../kernel/sha256_gpu.cu -o validate -lssl -lcrypto
// Run:   ./validate [data_dir]        (data_dir optional; default "data")
// Exit:  0 = all passed, 1 = a failure (or an explicitly-requested dataset
//        that could not be loaded).
// =====================================================================
#include "../../include/sha256_gpu.hpp"

#include <openssl/sha.h>

#include <iostream>
#include <iomanip>
#include <sstream>
#include <fstream>
#include <vector>
#include <string>
#include <cstring>
#include <stdexcept>

// ---- CPU reference: trusted SHA-256 via OpenSSL ----
static std::vector<unsigned char> cpu_sha256(const unsigned char* data, size_t len) {
    std::vector<unsigned char> out(32);
    SHA256(data, len, out.data());
    return out;
}

// ---- 32 raw bytes -> 64-char lowercase hex (for readable mismatch reports) ----
static std::string to_hex(const unsigned char* d) {
    std::ostringstream s;
    for (int i = 0; i < 32; i++)
        s << std::hex << std::setw(2) << std::setfill('0') << (int)d[i];
    return s.str();
}

// Pack a list of messages into the I/O-contract layout, then hash on the GPU.
static std::vector<unsigned char> gpu_hash_messages(const std::vector<std::string>& msgs,
                                                    std::vector<int>& offsets,
                                                    std::vector<int>& lengths) {
    int n = (int)msgs.size();
    offsets.resize(n);
    lengths.resize(n);
    std::vector<unsigned char> packed;
    int total = 0;
    for (int i = 0; i < n; i++) {
        offsets[i] = total;
        lengths[i] = (int)msgs[i].size();
        total += lengths[i];
        packed.insert(packed.end(), msgs[i].begin(), msgs[i].end());
    }
    return sha256_gpu_hash(packed.data(), packed.size(), offsets.data(), lengths.data(), n);
}

// ---- Part 1: edge-case suite ----
static bool run_edge_cases() {
    std::cout << "== Edge-case suite ==\n";
    std::vector<std::string> msgs = {
        "",                       // empty
        "a",                      // 1 byte
        std::string(55, 'a'),     // 55 — padding still fits one block
        std::string(56, 'a'),     // 56 — padding spills into a SECOND block
        std::string(64, 'a'),     // 64 — exactly one block, padding -> second
        std::string(130, 'a'),    // multi-block
        "abc",                    // classic NIST vector
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" // 56-byte NIST vector
    };
    std::vector<std::string> names = {
        "empty(0)", "1 byte", "55 bytes", "56 bytes", "64 bytes",
        "130 bytes", "\"abc\"", "56-byte NIST"
    };

    std::vector<int> offsets, lengths;
    std::vector<unsigned char> gpu = gpu_hash_messages(msgs, offsets, lengths);

    bool all_ok = true;
    for (size_t i = 0; i < msgs.size(); i++) {
        std::vector<unsigned char> ref =
            cpu_sha256(reinterpret_cast<const unsigned char*>(msgs[i].data()), msgs[i].size());
        bool ok = (memcmp(gpu.data() + i * 32, ref.data(), 32) == 0);
        if (!ok) all_ok = false;
        std::cout << "  [" << (ok ? "PASS" : "FAIL") << "] " << names[i] << "\n";
        if (!ok) {
            std::cerr << "    mismatch on " << names[i] << "\n"
                      << "      gpu: " << to_hex(gpu.data() + i * 32) << "\n"
                      << "      cpu: " << to_hex(ref.data()) << "\n";
        }
    }
    std::cout << (all_ok ? "  edge cases: ALL PASS\n\n" : "  edge cases: SOME FAILED\n\n");
    return all_ok;
}

// ---- helpers to load a dataset directory ----
static std::vector<unsigned char> read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) return {};
    std::streamsize n = f.tellg();
    f.seekg(0);
    std::vector<unsigned char> buf(n > 0 ? (size_t)n : 0);
    if (n > 0) f.read(reinterpret_cast<char*>(buf.data()), n);
    return buf;
}

// Returns num_messages, or -1 if the file is missing/malformed.
static int read_num_messages(const std::string& path) {
    std::ifstream f(path);
    if (!f) return -1;
    std::string line;
    std::getline(f, line);
    auto pos = line.find('=');
    if (pos == std::string::npos) return -1;
    try {
        return std::stoi(line.substr(pos + 1));
    } catch (const std::exception&) {
        return -1;
    }
}

// Every message must lie inside the messages buffer.
static bool dataset_in_bounds(const int* offsets, const int* lengths, int n, size_t total_bytes) {
    for (int i = 0; i < n; i++) {
        if (offsets[i] < 0 || lengths[i] < 0) return false;
        if ((size_t)offsets[i] + (size_t)lengths[i] > total_bytes) return false;
    }
    return true;
}

// ---- Part 2: full-dataset check (GPU vs CPU reference) ----
// Returns true on success. `required` = the dataset was explicitly requested,
// so a missing/invalid dataset is a FAILURE rather than a silent skip.
static bool run_dataset(const std::string& dir, bool required) {
    int num_messages = read_num_messages(dir + "/meta.txt");
    if (num_messages < 0) {
        if (required) {
            std::cerr << "== Dataset check == ERROR: cannot read " << dir << "/meta.txt\n";
            return false;
        }
        std::cout << "== Dataset check == (skipped: no " << dir << "/meta.txt)\n";
        return true;  // default dir absent — not a failure
    }
    if (num_messages == 0) {
        std::cerr << "== Dataset check == ERROR: num_messages is 0 in " << dir << "/meta.txt\n";
        return false;
    }
    std::cout << "== Dataset check (" << dir << ", " << num_messages << " messages) ==\n";

    std::vector<unsigned char> messages = read_file(dir + "/messages.bin");
    std::vector<unsigned char> off_raw  = read_file(dir + "/offsets.bin");
    std::vector<unsigned char> len_raw  = read_file(dir + "/lengths.bin");
    if (off_raw.size() != (size_t)num_messages * sizeof(int) ||
        len_raw.size() != (size_t)num_messages * sizeof(int)) {
        std::cerr << "  ERROR: offsets/lengths size does not match num_messages\n";
        return false;
    }
    const int* offsets = reinterpret_cast<const int*>(off_raw.data());
    const int* lengths = reinterpret_cast<const int*>(len_raw.data());

    if (!dataset_in_bounds(offsets, lengths, num_messages, messages.size())) {
        std::cerr << "  ERROR: a message offset/length falls outside messages.bin "
                  << "(corrupt or truncated dataset)\n";
        return false;
    }

    // GPU digests via the shared API.
    std::vector<unsigned char> gpu =
        sha256_gpu_hash(messages.data(), messages.size(), offsets, lengths, num_messages);

    // Reference: prefer Karan's expected_digests.bin; else compute with OpenSSL.
    std::vector<unsigned char> expected = read_file(dir + "/expected_digests.bin");
    bool have_file = !expected.empty();
    if (have_file && expected.size() != (size_t)num_messages * 32) {
        std::cerr << "  WARNING: expected_digests.bin wrong size ("
                  << expected.size() << " vs " << (size_t)num_messages * 32
                  << "); falling back to OpenSSL\n";
        have_file = false;
    }
    std::cout << "  reference: " << (have_file ? "expected_digests.bin" : "OpenSSL (computed)") << "\n";

    size_t mismatches = 0;
    long long first = -1;
    for (int i = 0; i < num_messages; i++) {
        const unsigned char* ref;
        std::vector<unsigned char> tmp;
        if (have_file) {
            ref = expected.data() + (size_t)i * 32;
        } else {
            tmp = cpu_sha256(messages.data() + offsets[i], (size_t)lengths[i]);
            ref = tmp.data();
        }
        if (memcmp(gpu.data() + (size_t)i * 32, ref, 32) != 0) {
            mismatches++;
            if (first < 0) {
                first = i;
                std::cerr << "  first mismatch at index " << i << ":\n"
                          << "    gpu: " << to_hex(gpu.data() + (size_t)i * 32) << "\n"
                          << "    ref: " << to_hex(ref) << "\n";
            }
        }
    }
    if (mismatches == 0) std::cout << "  ALL MATCH (" << num_messages << " messages)\n\n";
    else                 std::cout << "  " << mismatches << " mismatch(es)\n\n";
    return mismatches == 0;
}

int main(int argc, char** argv) {
    const std::string dir = (argc > 1) ? argv[1] : "data";
    const bool required = (argc > 1);   // an explicit dir must exist

    bool ok = true;
    try {
        ok &= run_edge_cases();
        ok &= run_dataset(dir, required);
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        std::cout << "VALIDATION FAILED\n";
        return 1;
    }

    std::cout << (ok ? "VALIDATION PASSED\n" : "VALIDATION FAILED\n");
    return ok ? 0 : 1;
}
