// =====================================================================
// benchmark.cpp — GPU vs CPU SHA-256 throughput benchmark
//
// Plain C++ driver (same pattern as validate.cpp): calls sha256_gpu_hash()
// from include/sha256_gpu.hpp and links src/kernel/sha256_gpu.cu.
//
// Loads a dataset (I/O-contract §4) and reports throughput for:
//   1. CPU baseline — OpenSSL SHA256(), one message at a time (serial loop)
//   2. GPU batch API — sha256_gpu_hash() (alloc, H2D, kernel, D2H)
//
// Output includes both rows and a GPU-vs-CPU speedup for the report.
//
// Build: make benchmark
// Run:   ./build/benchmark [data_dir]
// Exit:  0 on success, 1 on invalid dataset or GPU API failure
// =====================================================================
#include "../../include/sha256_gpu.hpp"

#include <openssl/sha.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

// ---- Dataset I/O (same layout as hash_dataset.cu / IO_CONTRACT §4) ----

static std::vector<unsigned char> read_file(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) {
        std::cerr << "error: cannot open " << path << "\n";
        std::exit(1);
    }
    std::streamsize n = f.tellg();
    f.seekg(0);
    std::vector<unsigned char> buf(n > 0 ? static_cast<size_t>(n) : 0);
    if (n > 0) f.read(reinterpret_cast<char*>(buf.data()), n);
    return buf;
}

static int read_num_messages(const std::string& path) {
    std::ifstream f(path);
    if (!f) {
        std::cerr << "error: cannot open " << path << "\n";
        std::exit(1);
    }
    std::string line;
    std::getline(f, line);
    auto pos = line.find('=');
    if (pos == std::string::npos) {
        std::cerr << "error: bad meta.txt: " << line << "\n";
        std::exit(1);
    }
    try {
        return std::stoi(line.substr(pos + 1));
    } catch (const std::exception&) {
        std::cerr << "error: bad num_messages in meta.txt: " << line << "\n";
        std::exit(1);
    }
}

static bool dataset_in_bounds(const int* offsets, const int* lengths, int n, size_t total_bytes) {
    for (int i = 0; i < n; i++) {
        if (offsets[i] < 0 || lengths[i] < 0) return false;
        if (static_cast<size_t>(offsets[i]) + static_cast<size_t>(lengths[i]) > total_bytes)
            return false;
    }
    return true;
}

struct TimingResult {
    double ms;
    double hashes_per_sec;
    double gbps;
};

static TimingResult make_result(double ms, int num_messages, size_t input_bytes) {
    TimingResult r{};
    r.ms = ms;
    if (ms > 0.0) {
        const double sec = ms / 1000.0;
        r.hashes_per_sec = static_cast<double>(num_messages) / sec;
        r.gbps = static_cast<double>(input_bytes) / sec / 1e9;
    }
    return r;
}

// CPU baseline for report comparison: serial OpenSSL SHA256 per message.
static TimingResult time_cpu(const unsigned char* messages, const int* offsets,
                             const int* lengths, int num_messages, size_t input_bytes) {
    const auto t0 = std::chrono::steady_clock::now();
    for (int i = 0; i < num_messages; i++) {
        unsigned char digest[32];
        SHA256(messages + offsets[i], static_cast<size_t>(lengths[i]), digest);
    }
    const auto t1 = std::chrono::steady_clock::now();
    const double ms =
        std::chrono::duration<double, std::milli>(t1 - t0).count();
    return make_result(ms, num_messages, input_bytes);
}

// GPU via sha256_gpu_hash(): warm-up, then timed call through the shared API.
static TimingResult time_gpu_api(const unsigned char* messages, size_t total_bytes,
                                 const int* offsets, const int* lengths,
                                 int num_messages, size_t input_bytes) {
    (void)sha256_gpu_hash(messages, total_bytes, offsets, lengths, num_messages);

    const auto t0 = std::chrono::steady_clock::now();
    const std::vector<unsigned char> digests =
        sha256_gpu_hash(messages, total_bytes, offsets, lengths, num_messages);
    const auto t1 = std::chrono::steady_clock::now();

    if (digests.size() != static_cast<size_t>(num_messages) * 32) {
        std::cerr << "error: sha256_gpu_hash returned unexpected size "
                  << digests.size() << "\n";
        std::exit(1);
    }

    const double ms =
        std::chrono::duration<double, std::milli>(t1 - t0).count();
    return make_result(ms, num_messages, input_bytes);
}

static void print_row(const char* label, const TimingResult& r) {
    std::cout << std::left << std::setw(28) << label
              << std::right << std::fixed << std::setprecision(2) << std::setw(10) << r.ms << " ms"
              << std::setw(14) << std::setprecision(0) << r.hashes_per_sec << " hashes/s"
              << std::setw(10) << std::setprecision(3) << r.gbps << " GB/s"
              << "\n";
}

int main(int argc, char** argv) {
    const std::string data_dir = (argc > 1) ? argv[1] : "data";

    const int num_messages = read_num_messages(data_dir + "/meta.txt");
    if (num_messages <= 0) {
        std::cerr << "error: num_messages must be > 0 (got " << num_messages << ")\n";
        return 1;
    }

    std::vector<unsigned char> messages = read_file(data_dir + "/messages.bin");
    std::vector<unsigned char> off_raw = read_file(data_dir + "/offsets.bin");
    std::vector<unsigned char> len_raw = read_file(data_dir + "/lengths.bin");

    if (off_raw.size() != static_cast<size_t>(num_messages) * sizeof(int) ||
        len_raw.size() != static_cast<size_t>(num_messages) * sizeof(int)) {
        std::cerr << "error: offsets/lengths size does not match num_messages\n";
        return 1;
    }

    const int* offsets = reinterpret_cast<const int*>(off_raw.data());
    const int* lengths = reinterpret_cast<const int*>(len_raw.data());
    const size_t input_bytes = messages.size();

    if (!dataset_in_bounds(offsets, lengths, num_messages, input_bytes)) {
        std::cerr << "error: a message offset/length falls outside messages.bin\n";
        return 1;
    }

    TimingResult cpu;
    TimingResult gpu;
    try {
        cpu = time_cpu(messages.data(), offsets, lengths, num_messages, input_bytes);
        gpu = time_gpu_api(messages.data(), input_bytes, offsets, lengths,
                           num_messages, input_bytes);
    } catch (const std::exception& e) {
        std::cerr << "error: benchmark failed: " << e.what() << "\n";
        return 1;
    }

    std::cout << "================================================================\n";
    std::cout << "  SHA-256 Benchmark — CPU vs GPU comparison (for report)\n";
    std::cout << "================================================================\n";
    std::cout << "  dataset:      " << data_dir << "\n";
    std::cout << "  num_messages: " << num_messages << "\n";
    std::cout << "  input_bytes:  " << input_bytes << "\n";
    std::cout << "  GPU API:      sha256_gpu_hash() via include/sha256_gpu.hpp\n";
    std::cout << "----------------------------------------------------------------\n";
    std::cout << std::left << std::setw(28) << "Mode"
              << std::right << std::setw(10) << "Time"
              << std::setw(14) << "Throughput"
              << std::setw(10) << "Input"
              << "\n";
    std::cout << std::left << std::setw(28) << ""
              << std::right << std::setw(10) << ""
              << std::setw(14) << "hashes/s"
              << std::setw(10) << "GB/s"
              << "\n";
    std::cout << "----------------------------------------------------------------\n";
    print_row("CPU (OpenSSL, serial)", cpu);
    print_row("GPU (sha256_gpu_hash)", gpu);
    std::cout << "----------------------------------------------------------------\n";
    std::cout << "  Report comparison:\n";
    if (cpu.ms > 0.0 && gpu.ms > 0.0) {
        std::cout << "    CPU: " << std::fixed << std::setprecision(0) << cpu.hashes_per_sec
                  << " hashes/s, " << std::setprecision(3) << cpu.gbps << " GB/s\n";
        std::cout << "    GPU: " << std::setprecision(0) << gpu.hashes_per_sec
                  << " hashes/s, " << std::setprecision(3) << gpu.gbps << " GB/s\n";
        std::cout << "    speedup (GPU vs CPU): "
                  << std::setprecision(2) << (cpu.ms / gpu.ms) << "x\n";
    }
    std::cout << "================================================================\n";

    return 0;
}
