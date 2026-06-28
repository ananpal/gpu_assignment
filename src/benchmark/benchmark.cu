// =====================================================================
// benchmark.cu — GPU vs CPU SHA-256 throughput benchmark (Mohshinsha)
//
// Loads a dataset from disk, times:
//   1. CPU baseline (OpenSSL, serial loop)
//   2. GPU kernel only (CUDA events around launch; data already on device)
//   3. GPU end-to-end (H2D + kernel + D2H)
//
// Build: make benchmark
// Run:   ./build/benchmark [data_dir] [--block-size 128|256|512]
// =====================================================================
#include "../../include/sha256.cuh"

#include <openssl/sha.h>

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

#define CUDA_CHECK(call)                                                      \
    do {                                                                      \
        cudaError_t _e = (call);                                              \
        if (_e != cudaSuccess) {                                              \
            std::cerr << "CUDA error: " << cudaGetErrorString(_e)            \
                      << " at " << __FILE__ << ":" << __LINE__ << "\n";       \
            std::exit(1);                                                     \
        }                                                                     \
    } while (0)

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

static void launch_kernel(unsigned char* d_messages, int* d_offsets, int* d_lengths,
                          unsigned char* d_digests, int num_messages, int threads_per_block) {
    const int num_blocks =
        static_cast<int>((static_cast<size_t>(num_messages) + threads_per_block - 1) /
                         static_cast<size_t>(threads_per_block));
    sha256_kernel<<<num_blocks, threads_per_block>>>(
        d_messages, d_offsets, d_lengths, d_digests, num_messages);
    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaDeviceSynchronize());
}

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

static TimingResult time_gpu_kernel_only(unsigned char* d_messages, int* d_offsets,
                                         int* d_lengths, unsigned char* d_digests,
                                         int num_messages, int threads_per_block,
                                         size_t input_bytes) {
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    launch_kernel(d_messages, d_offsets, d_lengths, d_digests, num_messages, threads_per_block);

    CUDA_CHECK(cudaEventRecord(start));
    launch_kernel(d_messages, d_offsets, d_lengths, d_digests, num_messages, threads_per_block);
    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float ms = 0.f;
    CUDA_CHECK(cudaEventElapsedTime(&ms, start, stop));
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    return make_result(static_cast<double>(ms), num_messages, input_bytes);
}

static TimingResult time_gpu_with_transfer(const unsigned char* h_messages, size_t total_bytes,
                                           const int* h_offsets, const int* h_lengths,
                                           int num_messages, int threads_per_block,
                                           size_t input_bytes) {
    unsigned char *d_messages = nullptr, *d_digests = nullptr;
    int *d_offsets = nullptr, *d_lengths = nullptr;
    const size_t digest_bytes = static_cast<size_t>(num_messages) * 32;

    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    CUDA_CHECK(cudaMalloc(&d_messages, total_bytes ? total_bytes : 1));
    CUDA_CHECK(cudaMalloc(&d_offsets, static_cast<size_t>(num_messages) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_lengths, static_cast<size_t>(num_messages) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_digests, digest_bytes));

    CUDA_CHECK(cudaEventRecord(start));

    if (total_bytes)
        CUDA_CHECK(cudaMemcpy(d_messages, h_messages, total_bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets, h_offsets,
                          static_cast<size_t>(num_messages) * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_lengths, h_lengths,
                          static_cast<size_t>(num_messages) * sizeof(int), cudaMemcpyHostToDevice));

    launch_kernel(d_messages, d_offsets, d_lengths, d_digests, num_messages, threads_per_block);

    std::vector<unsigned char> h_digests(digest_bytes);
    CUDA_CHECK(cudaMemcpy(h_digests.data(), d_digests, digest_bytes, cudaMemcpyDeviceToHost));

    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float ms = 0.f;
    CUDA_CHECK(cudaEventElapsedTime(&ms, start, stop));

    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    cudaFree(d_messages);
    cudaFree(d_offsets);
    cudaFree(d_lengths);
    cudaFree(d_digests);

    return make_result(static_cast<double>(ms), num_messages, input_bytes);
}

static void print_row(const char* label, const TimingResult& r) {
    std::cout << std::left << std::setw(28) << label
              << std::right << std::fixed << std::setprecision(2) << std::setw(10) << r.ms << " ms"
              << std::setw(14) << std::setprecision(0) << r.hashes_per_sec << " hashes/s"
              << std::setw(10) << std::setprecision(3) << r.gbps << " GB/s"
              << "\n";
}

static void parse_args(int argc, char** argv, std::string& data_dir, int& threads_per_block) {
    data_dir = "data";
    threads_per_block = 256;

    for (int i = 1; i < argc; i++) {
        const std::string arg = argv[i];
        if (arg == "--block-size" && i + 1 < argc) {
            threads_per_block = std::stoi(argv[++i]);
            if (threads_per_block != 128 && threads_per_block != 256 &&
                threads_per_block != 512) {
                std::cerr << "error: --block-size must be 128, 256, or 512\n";
                std::exit(1);
            }
        } else if (arg.rfind("--", 0) == 0) {
            std::cerr << "error: unknown option " << arg << "\n";
            std::exit(1);
        } else {
            data_dir = arg;
        }
    }
}

int main(int argc, char** argv) {
    std::string data_dir;
    int threads_per_block;
    parse_args(argc, argv, data_dir, threads_per_block);

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

    unsigned char *d_messages = nullptr, *d_digests = nullptr;
    int *d_offsets = nullptr, *d_lengths = nullptr;
    const size_t digest_bytes = static_cast<size_t>(num_messages) * 32;

    CUDA_CHECK(cudaMalloc(&d_messages, input_bytes ? input_bytes : 1));
    CUDA_CHECK(cudaMalloc(&d_offsets, static_cast<size_t>(num_messages) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_lengths, static_cast<size_t>(num_messages) * sizeof(int)));
    CUDA_CHECK(cudaMalloc(&d_digests, digest_bytes));

    if (input_bytes)
        CUDA_CHECK(cudaMemcpy(d_messages, messages.data(), input_bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_offsets, offsets,
                          static_cast<size_t>(num_messages) * sizeof(int), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_lengths, lengths,
                          static_cast<size_t>(num_messages) * sizeof(int), cudaMemcpyHostToDevice));

    launch_kernel(d_messages, d_offsets, d_lengths, d_digests, num_messages, threads_per_block);

    const TimingResult cpu = time_cpu(messages.data(), offsets, lengths, num_messages, input_bytes);
    const TimingResult gpu_kernel =
        time_gpu_kernel_only(d_messages, d_offsets, d_lengths, d_digests, num_messages,
                             threads_per_block, input_bytes);
    const TimingResult gpu_e2e =
        time_gpu_with_transfer(messages.data(), input_bytes, offsets, lengths, num_messages,
                               threads_per_block, input_bytes);

    cudaFree(d_messages);
    cudaFree(d_offsets);
    cudaFree(d_lengths);
    cudaFree(d_digests);

    std::cout << "================================================================\n";
    std::cout << "  SHA-256 Benchmark\n";
    std::cout << "================================================================\n";
    std::cout << "  dataset:         " << data_dir << "\n";
    std::cout << "  num_messages:    " << num_messages << "\n";
    std::cout << "  input_bytes:     " << input_bytes << "\n";
    std::cout << "  threadsPerBlock: " << threads_per_block << "\n";
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
    print_row("GPU (kernel only)", gpu_kernel);
    print_row("GPU (with H<->D xfer)", gpu_e2e);
    std::cout << "----------------------------------------------------------------\n";

    if (cpu.ms > 0.0 && gpu_kernel.ms > 0.0) {
        std::cout << "  speedup (kernel vs CPU): "
                  << std::fixed << std::setprecision(2)
                  << (cpu.ms / gpu_kernel.ms) << "x\n";
    }
    if (cpu.ms > 0.0 && gpu_e2e.ms > 0.0) {
        std::cout << "  speedup (e2e vs CPU):    "
                  << std::fixed << std::setprecision(2)
                  << (cpu.ms / gpu_e2e.ms) << "x\n";
    }
    std::cout << "================================================================\n";

    return 0;
}
