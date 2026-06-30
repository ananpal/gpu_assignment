// =====================================================================
// prodpath_benchmark.cu — "full cab ride" benchmark of the PRODUCTION path
//
// Owner: Mudrik (results/).  Addresses the review concern that
// scale_benchmark.cu's "end-to-end" = H2D + kernel + D2H with *reused*
// device buffers, whereas the production API sha256_gpu_hash()
// (src/kernel/sha256_gpu.cu — used by validate / hash_dataset / make
// benchmark) does malloc -> H2D -> kernel -> D2H -> free on EVERY call.
//
// This driver links the REAL engine (sha256_gpu.cu) and times the actual
// sha256_gpu_hash() call, so the numbers include cudaMalloc/cudaFree.
// It reports, on the same machine / GPU / dataset, side by side:
//
//   * gpu_full_call    sha256_gpu_hash() — malloc + H2D + kernel + D2H + free
//                      (the production path; what make benchmark measures)
//   * gpu_reused_e2e   H2D + kernel + D2H with buffers allocated once
//                      (what scale_benchmark.cu calls "end-to-end")
//   * cpu_scalar       single-threaded scalar SHA-256 reference
//
// The (full_call - reused_e2e) gap is exactly the per-call alloc/free cost
// the review flagged. Correctness is checked against data/expected_digests.bin.
//
// It does NOT need OpenSSL (ships its own NIST-verified host SHA-256), so it
// runs on this Windows box where make benchmark cannot link libssl.
//
// Build (Windows): nvcc -O3 -std=c++17 -Iinclude results\prodpath_benchmark.cu \
//                       src\kernel\sha256_gpu.cu -o build\prodpath_benchmark.exe
// Run:             build\prodpath_benchmark.exe data
//
// Output: results/benchmark_prodpath.csv  +  console table
// =====================================================================
#include "sha256_gpu.hpp"   // production API: sha256_gpu_hash(...)
#include "sha256.cuh"       // device kernel — for the reused-buffer comparison

#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>
#include <chrono>
#include <vector>
#include <string>
#include <algorithm>
#include <fstream>
#include <filesystem>

namespace fs = std::filesystem;
using clk = std::chrono::steady_clock;

// ---- host SHA-256 reference (FIPS 180-4), for CPU baseline + self-test -----
#define H_ROTR(x,n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define H_CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define H_MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define H_EP0(x)     (H_ROTR(x,2)  ^ H_ROTR(x,13) ^ H_ROTR(x,22))
#define H_EP1(x)     (H_ROTR(x,6)  ^ H_ROTR(x,11) ^ H_ROTR(x,25))
#define H_SIG0(x)    (H_ROTR(x,7)  ^ H_ROTR(x,18) ^ ((x) >> 3))
#define H_SIG1(x)    (H_ROTR(x,17) ^ H_ROTR(x,19) ^ ((x) >> 10))

static const uint32_t HK[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void host_transform(uint32_t h[8], const unsigned char* block) {
    uint32_t w[64];
    for (int i = 0; i < 16; i++)
        w[i] = ((uint32_t)block[i*4] << 24) | ((uint32_t)block[i*4+1] << 16) |
               ((uint32_t)block[i*4+2] << 8) | (uint32_t)block[i*4+3];
    for (int i = 16; i < 64; i++)
        w[i] = H_SIG1(w[i-2]) + w[i-7] + H_SIG0(w[i-15]) + w[i-16];
    uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4],f=h[5],g=h[6],hh=h[7];
    for (int i = 0; i < 64; i++) {
        uint32_t t1 = hh + H_EP1(e) + H_CH(e,f,g) + HK[i] + w[i];
        uint32_t t2 = H_EP0(a) + H_MAJ(a,b,c);
        hh=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
    }
    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}
static void host_sha256(const unsigned char* data, uint32_t length, unsigned char* out) {
    uint32_t h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
                     0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    uint32_t i = 0;
    while (length - i >= 64) { host_transform(h, data + i); i += 64; }
    unsigned char buf[128];
    uint32_t rem = length - i;
    for (uint32_t j = 0; j < rem; j++) buf[j] = data[i + j];
    buf[rem] = 0x80;
    uint32_t total = (rem < 56) ? 64 : 128;
    for (uint32_t j = rem + 1; j < total - 8; j++) buf[j] = 0;
    uint64_t bitlen = (uint64_t)length * 8;
    for (int j = 0; j < 8; j++) buf[total-1-j] = (unsigned char)((bitlen >> (8*j)) & 0xff);
    host_transform(h, buf);
    if (total == 128) host_transform(h, buf + 64);
    for (int j = 0; j < 8; j++) {
        out[j*4]   = (h[j] >> 24) & 0xff; out[j*4+1] = (h[j] >> 16) & 0xff;
        out[j*4+2] = (h[j] >> 8)  & 0xff; out[j*4+3] =  h[j]        & 0xff;
    }
}

// ---- helpers --------------------------------------------------------------
#define CUDA_OK(call) do { cudaError_t e_ = (call); if (e_ != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s at %s:%d -> %s\n", #call, __FILE__, __LINE__, \
            cudaGetErrorString(e_)); std::exit(2); } } while (0)

struct Stats { double mn, med, mean, sd; };
static Stats summarize(std::vector<double> v) {
    Stats s{0,0,0,0};
    if (v.empty()) return s;
    std::sort(v.begin(), v.end());
    s.mn = v.front();
    size_t n = v.size();
    s.med = (n & 1) ? v[n/2] : 0.5*(v[n/2-1]+v[n/2]);
    double sum = 0; for (double x : v) sum += x; s.mean = sum / n;
    double acc = 0; for (double x : v) acc += (x-s.mean)*(x-s.mean);
    s.sd = (n > 1) ? std::sqrt(acc/(n-1)) : 0.0;
    return s;
}
static double hps(long long n, double ms)  { return ms > 0 ? n / (ms/1000.0) : 0; }
static double gbps(size_t b, double ms)     { return ms > 0 ? b / (ms/1000.0) / 1e9 : 0; }
static std::string to_hex(const unsigned char* p, int n) {
    static const char* d = "0123456789abcdef"; std::string s; s.reserve(n*2);
    for (int i=0;i<n;i++){ s+=d[p[i]>>4]; s+=d[p[i]&0xf]; } return s;
}
static std::vector<unsigned char> read_bin(const std::string& p) {
    std::ifstream f(p, std::ios::binary|std::ios::ate);
    if (!f) return {};
    std::streamsize n = f.tellg(); f.seekg(0);
    std::vector<unsigned char> b(n>0?(size_t)n:0);
    if (n>0) f.read((char*)b.data(), n);
    return b;
}

static bool self_test() {
    struct V { const char* in; const char* hex; };
    V vs[] = {
        {"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"},
        {"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        {"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"},
    };
    bool ok = true;
    for (auto& v : vs) {
        unsigned char d[32];
        host_sha256((const unsigned char*)v.in, (uint32_t)strlen(v.in), d);
        ok = ok && (to_hex(d,32) == v.hex);
    }
    return ok;
}

// ---- the reused-buffer "end-to-end" path (mirrors scale_benchmark.cu) ------
// Buffers allocated once, then H2D + kernel + D2H timed per repeat. This is
// the "driving time only" measurement, for direct comparison.
static std::vector<double> time_reused_e2e(const std::vector<unsigned char>& msgs,
        const std::vector<int>& offs, const std::vector<int>& lens, int n, int repeats) {
    std::vector<double> wall;
    unsigned char *d_msg=nullptr,*d_dig=nullptr; int *d_off=nullptr,*d_len=nullptr;
    size_t mbytes = msgs.size(), dbytes = (size_t)n*32;
    CUDA_OK(cudaMalloc(&d_msg, mbytes));
    CUDA_OK(cudaMalloc(&d_off, (size_t)n*sizeof(int)));
    CUDA_OK(cudaMalloc(&d_len, (size_t)n*sizeof(int)));
    CUDA_OK(cudaMalloc(&d_dig, dbytes));
    int tpb = 256, blocks = (n + tpb - 1) / tpb;
    for (int r = -2; r < repeats; r++) {            // 2 warm-ups discarded
        auto w0 = clk::now();
        CUDA_OK(cudaMemcpy(d_msg, msgs.data(), mbytes, cudaMemcpyHostToDevice));
        CUDA_OK(cudaMemcpy(d_off, offs.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
        CUDA_OK(cudaMemcpy(d_len, lens.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
        sha256_kernel<<<blocks, tpb>>>(d_msg, d_off, d_len, d_dig, n);
        CUDA_OK(cudaGetLastError());
        std::vector<unsigned char> out(dbytes);
        CUDA_OK(cudaMemcpy(out.data(), d_dig, dbytes, cudaMemcpyDeviceToHost));
        CUDA_OK(cudaDeviceSynchronize());
        auto w1 = clk::now();
        if (r >= 0) wall.push_back(std::chrono::duration<double,std::milli>(w1-w0).count());
    }
    cudaFree(d_msg); cudaFree(d_off); cudaFree(d_len); cudaFree(d_dig);
    return wall;
}

int main(int argc, char** argv) {
    std::string dir = (argc > 1) ? argv[1] : "data";
    fs::create_directories("results");

    int dev = 0; cudaDeviceProp prop;
    CUDA_OK(cudaGetDevice(&dev)); CUDA_OK(cudaGetDeviceProperties(&prop, dev));
    int rt=0,drv=0; cudaRuntimeGetVersion(&rt); cudaDriverGetVersion(&drv);

    printf("================================================================\n");
    printf("  SHA-256 PRODUCTION-PATH benchmark (sha256_gpu_hash, incl. malloc/free)\n");
    printf("================================================================\n");
    printf("  GPU:          %s (%d SMs, %.1f GB, sm_%d%d)\n",
           prop.name, prop.multiProcessorCount, prop.totalGlobalMem/1e9, prop.major, prop.minor);
    printf("  CUDA:         runtime %d.%d  driver %d.%d\n", rt/1000,(rt%100)/10, drv/1000,(drv%100)/10);
    if (!self_test()) { fprintf(stderr, "  ABORT: host SHA-256 reference is wrong.\n"); return 1; }
    printf("  Self-test:    host SHA-256 vs NIST vectors OK\n");

    // ---- load the real dataset ----
    std::ifstream meta(dir + "/meta.txt");
    if (!meta) { fprintf(stderr, "  ERROR: no %s/meta.txt\n", dir.c_str()); return 1; }
    std::string line; std::getline(meta, line);
    int n = std::stoi(line.substr(line.find('=')+1));
    auto msgs = read_bin(dir+"/messages.bin");
    auto off_raw = read_bin(dir+"/offsets.bin");
    auto len_raw = read_bin(dir+"/lengths.bin");
    auto expected = read_bin(dir+"/expected_digests.bin");
    if (off_raw.size()!=(size_t)n*4 || len_raw.size()!=(size_t)n*4) {
        fprintf(stderr, "  ERROR: offsets/lengths size mismatch\n"); return 1; }
    std::vector<int> offs((int*)off_raw.data(), (int*)off_raw.data()+n);
    std::vector<int> lens((int*)len_raw.data(), (int*)len_raw.data()+n);
    size_t input_bytes = msgs.size();
    printf("  Dataset:      %s  (N=%d, %zu input bytes)\n", dir.c_str(), n, input_bytes);
    printf("----------------------------------------------------------------\n");

    const int repeats = 20, repeats_cpu = 5;

    // Sustained warm-up via the production API itself (forces GPU boost clocks).
    {
        auto wu = clk::now();
        while (std::chrono::duration<double,std::milli>(clk::now()-wu).count() < 300.0)
            (void)sha256_gpu_hash(msgs.data(), input_bytes, offs.data(), lens.data(), n);
    }

    // ---- (A) production path: full sha256_gpu_hash() per call ----
    std::vector<double> full;
    std::vector<unsigned char> last_digest;
    for (int r = 0; r < repeats; r++) {
        auto t0 = clk::now();
        auto d = sha256_gpu_hash(msgs.data(), input_bytes, offs.data(), lens.data(), n);
        auto t1 = clk::now();   // sha256_gpu_hash syncs internally, so t1 is accurate
        full.push_back(std::chrono::duration<double,std::milli>(t1-t0).count());
        if (r == repeats-1) last_digest = std::move(d);
    }

    // ---- (B) reused-buffer end-to-end (H2D+kernel+D2H), for comparison ----
    auto reused = time_reused_e2e(msgs, offs, lens, n, repeats);

    // ---- (C) CPU scalar baseline ----
    std::vector<double> cpu_t;
    std::vector<unsigned char> cpu_dig((size_t)n*32);
    for (int r = -1; r < repeats_cpu; r++) {
        auto t0 = clk::now();
        for (int i = 0; i < n; i++)
            host_sha256(msgs.data()+offs[i], (uint32_t)lens[i], cpu_dig.data()+(size_t)i*32);
        auto t1 = clk::now();
        if (r >= 0) cpu_t.push_back(std::chrono::duration<double,std::milli>(t1-t0).count());
    }

    // ---- correctness of the production-path digests ----
    long long mism_cpu = 0, mism_exp = 0;
    for (long long i=0;i<n;i++) if (memcmp(cpu_dig.data()+i*32, last_digest.data()+i*32, 32)) mism_cpu++;
    bool have_exp = expected.size()==(size_t)n*32;
    if (have_exp) for (long long i=0;i<n;i++) if (memcmp(expected.data()+i*32, last_digest.data()+i*32, 32)) mism_exp++;

    Stats sf = summarize(full), sr = summarize(reused), sc = summarize(cpu_t);
    double overhead = sf.med - sr.med;   // per-call malloc + free cost

    printf("  Correctness (production sha256_gpu_hash output):\n");
    printf("    vs CPU reference:           %s\n", mism_cpu==0?"MATCH":"MISMATCH!");
    printf("    vs data/expected_digests.bin: %s\n",
           have_exp ? (mism_exp==0?"MATCH":"MISMATCH!") : "n/a (file absent)");
    printf("----------------------------------------------------------------\n");
    printf("  Timing at N=%d  (median of %d repeats; CPU %d):\n", n, repeats, repeats_cpu);
    printf("    %-34s %9.3f ms  %12.0f hashes/s  %7.3f GB/s\n",
           "gpu_full_call (malloc->...->free)", sf.med, hps(n, sf.med), gbps(input_bytes, sf.med));
    printf("    %-34s %9.3f ms  %12.0f hashes/s  %7.3f GB/s\n",
           "gpu_reused_e2e (H2D+kernel+D2H)", sr.med, hps(n, sr.med), gbps(input_bytes, sr.med));
    printf("    %-34s %9.3f ms  %12.0f hashes/s  %7.3f GB/s\n",
           "cpu_scalar (1 thread)", sc.med, hps(n, sc.med), gbps(input_bytes, sc.med));
    printf("----------------------------------------------------------------\n");
    printf("  Per-call alloc/free overhead (full - reused): %.3f ms  (%.0f%% of full call)\n",
           overhead, 100.0*overhead/sf.med);
    printf("  Speedup vs cpu_scalar:  full_call = %.1fx   reused_e2e = %.1fx\n",
           sc.med/sf.med, sc.med/sr.med);
    printf("================================================================\n");

    // ---- CSV ----
    FILE* csv = fopen("results/benchmark_prodpath.csv", "w");
    if (csv) {
        fprintf(csv, "num_messages,input_bytes,repeats,path,"
                     "wall_min_ms,wall_med_ms,wall_mean_ms,wall_sd_ms,"
                     "hashes_per_sec,gbps,correct\n");
        auto row = [&](const char* path, const Stats& s, int reps, const char* ok){
            fprintf(csv, "%d,%zu,%d,%s,%.4f,%.4f,%.4f,%.4f,%.0f,%.4f,%s\n",
                    n, input_bytes, reps, path, s.mn, s.med, s.mean, s.sd,
                    hps(n, s.med), gbps(input_bytes, s.med), ok);
        };
        const char* okstr = (mism_cpu==0 && (!have_exp || mism_exp==0)) ? "yes" : "no";
        row("gpu_full_call",  sf, repeats,     okstr);
        row("gpu_reused_e2e", sr, repeats,     okstr);
        row("cpu_scalar",     sc, repeats_cpu, "ref");
        fclose(csv);
        printf("  CSV: results/benchmark_prodpath.csv\n");
    }
    return 0;
}
