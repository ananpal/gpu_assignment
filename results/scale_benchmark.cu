// =====================================================================
// scale_benchmark.cu — Mudrik's robust GPU-vs-CPU SHA-256 benchmark
//
// Owner: Mudrik (results/ — benchmark output + charts)
//
// Why this exists (vs src/benchmark/benchmark.cpp, Mohshinsha's):
//   * That harness links OpenSSL and reports ONE timed run per mode.
//   * This harness is self-contained (no OpenSSL needed — ships its own
//     host SHA-256 reference, verified against the NIST vectors) and is
//     built for ROBUST measurement:
//       - warm-up run discarded
//       - many repeats per data point -> min / median / mean / stddev
//       - GPU time split into H2D / kernel / D2H via CUDA events
//       - correctness gate: GPU digests compared to the CPU reference
//         (and, when data/ is present, to the real expected_digests.bin)
//       - scaling sweep across dataset sizes
//       - block-size sweep (128/256/512/1024) at fixed N
//
// Build (Linux/Colab):  nvcc -O3 -std=c++17 -Iinclude results/scale_benchmark.cu -o build/scale_benchmark
// Build (Windows):      nvcc -O3 -std=c++17 -Iinclude results\scale_benchmark.cu -o build\scale_benchmark.exe
// Run:                  ./build/scale_benchmark [data_dir]   (data_dir optional, default "data")
//
// Outputs (written under results/):
//   results/benchmark_summary.csv     scaling log — one row per dataset size
//                                     (hashes/sec, GB/s, speedup)
//   results/benchmark_<N>.csv         per-run snapshot — every timed repeat at
//                                     size N (raw H2D/kernel/D2H/total times)
//   results/benchmark_blocksize.csv   one row per block size at N=1,000,000
//   results/benchmark_realdata.csv    the on-disk data/ dataset, if present
// =====================================================================
#include "sha256.cuh"   // device kernel + round constants (single .cu, so OK)

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

// ---------------------------------------------------------------------
// Host SHA-256 reference (standard FIPS 180-4). This is the CPU baseline.
// Verified against the IO_CONTRACT NIST vectors at startup before any
// timing is trusted.
// ---------------------------------------------------------------------
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
        out[j*4]   = (h[j] >> 24) & 0xff;
        out[j*4+1] = (h[j] >> 16) & 0xff;
        out[j*4+2] = (h[j] >> 8)  & 0xff;
        out[j*4+3] =  h[j]        & 0xff;
    }
}

// ---------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------
#define CUDA_OK(call) do { cudaError_t e_ = (call); if (e_ != cudaSuccess) { \
    fprintf(stderr, "CUDA error %s at %s:%d -> %s\n", #call, __FILE__, __LINE__, \
            cudaGetErrorString(e_)); std::exit(2); } } while (0)

static std::string to_hex(const unsigned char* p, int n) {
    static const char* d = "0123456789abcdef";
    std::string s; s.reserve(n*2);
    for (int i = 0; i < n; i++) { s += d[p[i]>>4]; s += d[p[i]&0xf]; }
    return s;
}

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

// Deterministic synthetic dataset: lengths in [1,64] (single SHA block, matches
// the project's ~32-byte average), content from a reproducible LCG.
static uint32_t lcg(uint32_t& s) { s = s*1664525u + 1013904223u; return s; }
static void gen_dataset(int n, std::vector<unsigned char>& msgs,
                        std::vector<int>& offs, std::vector<int>& lens) {
    offs.resize(n); lens.resize(n);
    uint32_t s = 0xC0FFEEu;
    size_t total = 0;
    for (int i = 0; i < n; i++) { int L = 1 + (lcg(s) % 64); lens[i] = L; offs[i] = (int)total; total += L; }
    msgs.resize(total);
    s = 0xBEEF1234u;
    for (size_t i = 0; i < total; i++) msgs[i] = (unsigned char)(lcg(s) >> 17);
}

// ---------------------------------------------------------------------
// GPU timing for one dataset. Buffers are allocated once and reused across
// repeats so the per-stage numbers reflect steady-state throughput, not the
// one-off cudaMalloc cost. Returns per-repeat times (ms) by stage.
// ---------------------------------------------------------------------
struct GpuTimes { std::vector<double> h2d, kern, d2h, total; std::vector<unsigned char> digest; };

static GpuTimes time_gpu(const std::vector<unsigned char>& msgs, const std::vector<int>& offs,
                         const std::vector<int>& lens, int n, int repeats, int tpb) {
    GpuTimes t;
    unsigned char *d_msg=nullptr,*d_dig=nullptr; int *d_off=nullptr,*d_len=nullptr;
    size_t mbytes = msgs.size(), dbytes = (size_t)n*32;
    CUDA_OK(cudaMalloc(&d_msg, mbytes));
    CUDA_OK(cudaMalloc(&d_off, (size_t)n*sizeof(int)));
    CUDA_OK(cudaMalloc(&d_len, (size_t)n*sizeof(int)));
    CUDA_OK(cudaMalloc(&d_dig, dbytes));
    int blocks = (n + tpb - 1) / tpb;
    cudaEvent_t e0,e1,e2,e3;
    CUDA_OK(cudaEventCreate(&e0)); CUDA_OK(cudaEventCreate(&e1));
    CUDA_OK(cudaEventCreate(&e2)); CUDA_OK(cudaEventCreate(&e3));

    // Sustained warm-up: laptop GPUs idle-downclock between segments, so a single
    // warm-up kernel measures cold clocks. Hammer the kernel for ~300 ms of wall
    // time first to force max clocks; then the timed repeats run at steady state.
    CUDA_OK(cudaMemcpy(d_msg, msgs.data(), mbytes, cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemcpy(d_off, offs.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
    CUDA_OK(cudaMemcpy(d_len, lens.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
    {
        auto wu = clk::now();
        while (std::chrono::duration<double,std::milli>(clk::now()-wu).count() < 300.0) {
            for (int k = 0; k < 20; k++) sha256_kernel<<<blocks, tpb>>>(d_msg, d_off, d_len, d_dig, n);
            CUDA_OK(cudaDeviceSynchronize());
        }
    }

    for (int r = 0; r < repeats; r++) {
        auto w0 = clk::now();
        CUDA_OK(cudaEventRecord(e0));
        CUDA_OK(cudaMemcpy(d_msg, msgs.data(), mbytes, cudaMemcpyHostToDevice));
        CUDA_OK(cudaMemcpy(d_off, offs.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
        CUDA_OK(cudaMemcpy(d_len, lens.data(), (size_t)n*sizeof(int), cudaMemcpyHostToDevice));
        CUDA_OK(cudaEventRecord(e1));
        sha256_kernel<<<blocks, tpb>>>(d_msg, d_off, d_len, d_dig, n);
        CUDA_OK(cudaGetLastError());
        CUDA_OK(cudaEventRecord(e2));
        std::vector<unsigned char> out(dbytes);
        CUDA_OK(cudaMemcpy(out.data(), d_dig, dbytes, cudaMemcpyDeviceToHost));
        CUDA_OK(cudaEventRecord(e3));
        CUDA_OK(cudaEventSynchronize(e3));
        auto w1 = clk::now();
        if (r >= 0) {
            float h2d=0,kern=0,d2h=0;
            CUDA_OK(cudaEventElapsedTime(&h2d, e0, e1));
            CUDA_OK(cudaEventElapsedTime(&kern, e1, e2));
            CUDA_OK(cudaEventElapsedTime(&d2h, e2, e3));
            t.h2d.push_back(h2d); t.kern.push_back(kern); t.d2h.push_back(d2h);
            t.total.push_back(std::chrono::duration<double,std::milli>(w1-w0).count());
        }
        if (r == repeats-1) t.digest = std::move(out);
    }
    cudaEventDestroy(e0); cudaEventDestroy(e1); cudaEventDestroy(e2); cudaEventDestroy(e3);
    cudaFree(d_msg); cudaFree(d_off); cudaFree(d_len); cudaFree(d_dig);
    return t;
}

static std::vector<double> time_cpu(const std::vector<unsigned char>& msgs, const std::vector<int>& offs,
                                    const std::vector<int>& lens, int n, int repeats,
                                    std::vector<unsigned char>& digest_out) {
    std::vector<double> times;
    digest_out.resize((size_t)n*32);
    for (int r = -1; r < repeats; r++) {   // warm-up discarded
        auto t0 = clk::now();
        for (int i = 0; i < n; i++)
            host_sha256(msgs.data()+offs[i], (uint32_t)lens[i], digest_out.data()+(size_t)i*32);
        auto t1 = clk::now();
        if (r >= 0) times.push_back(std::chrono::duration<double,std::milli>(t1-t0).count());
    }
    return times;
}

static double hps(int n, double ms)  { return ms > 0 ? n / (ms/1000.0) : 0; }
static double gbps(size_t b, double ms){ return ms > 0 ? b / (ms/1000.0) / 1e9 : 0; }

// ---------------------------------------------------------------------
static void run_size(long long n, FILE* summary) {
    int repeats_cpu, repeats_gpu;
    if (n <= 10000)        { repeats_cpu = 20; repeats_gpu = 50; }
    else if (n <= 100000)  { repeats_cpu = 10; repeats_gpu = 30; }
    else if (n <= 1000000) { repeats_cpu = 5;  repeats_gpu = 20; }
    else                   { repeats_cpu = 3;  repeats_gpu = 10; }

    std::vector<unsigned char> msgs; std::vector<int> offs, lens;
    gen_dataset((int)n, msgs, offs, lens);
    size_t bytes = msgs.size();

    std::vector<unsigned char> cpu_dig;
    auto cpu_t = time_cpu(msgs, offs, lens, (int)n, repeats_cpu, cpu_dig);
    GpuTimes g = time_gpu(msgs, offs, lens, (int)n, repeats_gpu, 256);

    long long mism = 0;
    for (long long i = 0; i < n; i++)
        if (memcmp(cpu_dig.data()+i*32, g.digest.data()+i*32, 32) != 0) mism++;

    Stats cpu  = summarize(cpu_t),  gtot = summarize(g.total),
          gh2d = summarize(g.h2d),  gkern = summarize(g.kern), gd2h = summarize(g.d2h);
    const char* ok = (mism == 0) ? "yes" : "no";

    // ---- per-run snapshot: results/benchmark_<N>.csv ---------------------
    // One row per timed repeat (warm-up already discarded). This is the raw
    // distribution the summary stats are derived from — keep it for auditing.
    char path[256];
    std::snprintf(path, sizeof(path), "results/benchmark_%lld.csv", n);
    if (FILE* snap = fopen(path, "w")) {
        fprintf(snap, "num_messages,input_bytes,threads_per_block,engine,repeat,"
                      "h2d_ms,kernel_ms,d2h_ms,total_ms,hashes_per_sec,gbps\n");
        for (size_t r = 0; r < g.total.size(); r++)
            fprintf(snap, "%lld,%zu,256,gpu,%zu,%.4f,%.4f,%.4f,%.4f,%.0f,%.4f\n",
                    n, bytes, r, g.h2d[r], g.kern[r], g.d2h[r], g.total[r],
                    hps((int)n, g.total[r]), gbps(bytes, g.total[r]));
        for (size_t r = 0; r < cpu_t.size(); r++)
            fprintf(snap, "%lld,%zu,,cpu,%zu,,,,%.4f,%.0f,%.4f\n",
                    n, bytes, r, cpu_t[r], hps((int)n, cpu_t[r]), gbps(bytes, cpu_t[r]));
        fclose(snap);
    }

    printf("  N=%-9lld bytes=%-10zu cpu(med)=%9.2f ms  gpu_total(med)=%8.3f ms  "
           "gpu_kernel(med)=%8.3f ms  speedup(e2e)=%6.1fx  kernel-only=%7.1fx  [%s]\n",
           n, bytes, cpu.med, gtot.med, gkern.med,
           cpu.med/gtot.med, cpu.med/gkern.med, mism==0 ? "MATCH" : "MISMATCH!");

    // ---- scaling summary row: results/benchmark_summary.csv --------------
    fprintf(summary,
        "%lld,%zu,%.4f,%.4f,%.4f,%.4f,%.4f,%.0f,%.0f,%.0f,%.4f,%.4f,%.2f,%.2f,%s\n",
        n, bytes, cpu.med, gtot.med, gh2d.med, gkern.med, gd2h.med,
        hps((int)n, cpu.med), hps((int)n, gtot.med), hps((int)n, gkern.med),
        gbps(bytes, gkern.med), gbps(bytes, gtot.med),
        cpu.med/gtot.med, cpu.med/gkern.med, ok);
    fflush(summary);
}

// ---------------------------------------------------------------------
static std::vector<unsigned char> read_bin(const std::string& p) {
    std::ifstream f(p, std::ios::binary|std::ios::ate);
    if (!f) return {};
    std::streamsize n = f.tellg(); f.seekg(0);
    std::vector<unsigned char> b(n>0?(size_t)n:0);
    if (n>0) f.read((char*)b.data(), n);
    return b;
}

static void run_realdata(const std::string& dir, FILE* csv) {
    std::ifstream meta(dir + "/meta.txt");
    if (!meta) { printf("  (no %s/meta.txt — skipping real-data benchmark)\n", dir.c_str()); return; }
    std::string line; std::getline(meta, line);
    auto eq = line.find('='); if (eq == std::string::npos) { printf("  (bad meta.txt)\n"); return; }
    int n = std::stoi(line.substr(eq+1));
    auto msgs = read_bin(dir+"/messages.bin");
    auto off_raw = read_bin(dir+"/offsets.bin");
    auto len_raw = read_bin(dir+"/lengths.bin");
    auto expected = read_bin(dir+"/expected_digests.bin");
    if (off_raw.size()!=(size_t)n*4 || len_raw.size()!=(size_t)n*4) { printf("  (offsets/lengths size mismatch)\n"); return; }
    std::vector<int> offs((int*)off_raw.data(), (int*)off_raw.data()+n);
    std::vector<int> lens((int*)len_raw.data(), (int*)len_raw.data()+n);

    int repeats_cpu = (n<=1000000)?5:3, repeats_gpu = (n<=1000000)?20:10;
    std::vector<unsigned char> cpu_dig;
    auto cpu_t = time_cpu(msgs, offs, lens, n, repeats_cpu, cpu_dig);
    GpuTimes g = time_gpu(msgs, offs, lens, n, repeats_gpu, 256);

    long long mism_cpu = 0, mism_exp = 0;
    for (long long i=0;i<n;i++) if (memcmp(cpu_dig.data()+i*32, g.digest.data()+i*32, 32)) mism_cpu++;
    bool have_exp = expected.size()==(size_t)n*32;
    if (have_exp) for (long long i=0;i<n;i++) if (memcmp(expected.data()+i*32, g.digest.data()+i*32, 32)) mism_exp++;

    Stats cs=summarize(cpu_t), gt=summarize(g.total), gk=summarize(g.kern),
          gh=summarize(g.h2d), gd=summarize(g.d2h);
    printf("  REAL data/  N=%d  cpu(med)=%.2f ms  gpu_total(med)=%.3f ms  gpu_kernel(med)=%.3f ms\n",
           n, cs.med, gt.med, gk.med);
    printf("    speedup(e2e)=%.1fx  kernel-only=%.1fx  vs CPU-ref: %s  vs expected_digests.bin: %s\n",
           cs.med/gt.med, cs.med/gk.med,
           mism_cpu==0?"MATCH":"MISMATCH!",
           have_exp ? (mism_exp==0?"MATCH":"MISMATCH!") : "n/a (file absent)");

    fprintf(csv, "dataset,num_messages,input_bytes,cpu_med_ms,gpu_total_med_ms,gpu_h2d_med_ms,"
                 "gpu_kernel_med_ms,gpu_d2h_med_ms,cpu_hashes_per_sec,gpu_hashes_per_sec,"
                 "gpu_kernel_gbps,speedup_e2e,speedup_kernel,match_cpu_ref,match_expected_bin\n");
    fprintf(csv, "%s,%d,%zu,%.4f,%.4f,%.4f,%.4f,%.4f,%.0f,%.0f,%.4f,%.2f,%.2f,%s,%s\n",
            dir.c_str(), n, msgs.size(), cs.med, gt.med, gh.med, gk.med, gd.med,
            hps(n, cs.med), hps(n, gt.med), gbps(msgs.size(), gk.med),
            cs.med/gt.med, cs.med/gk.med,
            mism_cpu==0?"yes":"no", have_exp?(mism_exp==0?"yes":"no"):"n/a");
    fflush(csv);
}

// ---------------------------------------------------------------------
static void run_blocksize_sweep(FILE* csv) {
    const long long n = 1000000;
    std::vector<unsigned char> msgs; std::vector<int> offs, lens;
    gen_dataset((int)n, msgs, offs, lens);
    int sizes[] = {64, 128, 256, 512, 1024};
    fprintf(csv, "num_messages,threads_per_block,gpu_kernel_med_ms,gpu_kernel_min_ms,"
                 "gpu_kernel_sd_ms,kernel_hashes_per_sec,kernel_gbps,correct\n");
    printf("  block-size sweep at N=%lld (kernel-only, median of 20):\n", n);
    std::vector<unsigned char> cpu_dig;
    time_cpu(msgs, offs, lens, (int)n, 1, cpu_dig);  // reference for correctness check
    for (int tpb : sizes) {
        GpuTimes g = time_gpu(msgs, offs, lens, (int)n, 20, tpb);
        long long mism = 0;
        for (long long i=0;i<n;i++) if (memcmp(cpu_dig.data()+i*32, g.digest.data()+i*32, 32)) mism++;
        Stats k = summarize(g.kern);
        printf("    tpb=%-5d kernel(med)=%7.3f ms  %10.0f hashes/s  %6.3f GB/s  [%s]\n",
               tpb, k.med, hps((int)n, k.med), gbps(msgs.size(), k.med), mism==0?"MATCH":"MISMATCH!");
        fprintf(csv, "%lld,%d,%.4f,%.4f,%.4f,%.0f,%.4f,%s\n",
                n, tpb, k.med, k.mn, k.sd, hps((int)n, k.med), gbps(msgs.size(), k.med),
                mism==0?"yes":"no");
        fflush(csv);
    }
}

// ---------------------------------------------------------------------
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
        std::string got = to_hex(d, 32);
        bool m = (got == v.hex);
        printf("    host SHA-256(\"%.8s%s\") %s\n", v.in, strlen(v.in)>8?"...":"", m?"OK":"FAIL");
        ok = ok && m;
    }
    return ok;
}

int main(int argc, char** argv) {
    std::string data_dir = (argc > 1) ? argv[1] : "data";
    fs::create_directories("results");

    int dev = 0; cudaDeviceProp prop;
    CUDA_OK(cudaGetDevice(&dev));
    CUDA_OK(cudaGetDeviceProperties(&prop, dev));
    int rt = 0, drv = 0; cudaRuntimeGetVersion(&rt); cudaDriverGetVersion(&drv);

    printf("================================================================\n");
    printf("  SHA-256 GPU vs CPU — robust benchmark (Mudrik / results/)\n");
    printf("================================================================\n");
    printf("  GPU:            %s (%d SMs, %.1f GB, sm_%d%d)\n",
           prop.name, prop.multiProcessorCount,
           prop.totalGlobalMem/1e9, prop.major, prop.minor);
    printf("  CUDA runtime:   %d.%d   driver: %d.%d\n", rt/1000,(rt%100)/10, drv/1000,(drv%100)/10);
    printf("----------------------------------------------------------------\n");
    printf("  Self-test (host SHA-256 vs NIST vectors):\n");
    if (!self_test()) { fprintf(stderr, "  ABORT: host SHA-256 reference is wrong.\n"); return 1; }
    printf("  Self-test passed — CPU baseline is trustworthy.\n");
    printf("----------------------------------------------------------------\n");

    // 1. Real on-disk dataset (verifies GPU vs the project's expected_digests.bin)
    printf("  [1] Real dataset benchmark + correctness check:\n");
    {
        FILE* csv = fopen("results/benchmark_realdata.csv", "w");
        run_realdata(data_dir, csv);
        fclose(csv);
    }
    printf("----------------------------------------------------------------\n");

    // 2. Scaling sweep on synthetic datasets
    printf("  [2] Scaling sweep (synthetic, ~32-byte messages):\n");
    {
        FILE* csv = fopen("results/benchmark_summary.csv", "w");
        fprintf(csv, "num_messages,input_bytes,cpu_med_ms,"
                     "gpu_total_med_ms,gpu_h2d_med_ms,gpu_kernel_med_ms,gpu_d2h_med_ms,"
                     "cpu_hashes_per_sec,gpu_hashes_per_sec,gpu_kernel_hashes_per_sec,"
                     "gpu_kernel_gbps,gpu_total_gbps,speedup_e2e,speedup_kernel,correct\n");
        for (long long n : {10000LL, 100000LL, 1000000LL, 10000000LL})
            run_size(n, csv);
        fclose(csv);
    }
    printf("----------------------------------------------------------------\n");

    // 3. Block-size sweep
    printf("  [3] Block-size sweep:\n");
    {
        FILE* csv = fopen("results/benchmark_blocksize.csv", "w");
        run_blocksize_sweep(csv);
        fclose(csv);
    }
    printf("----------------------------------------------------------------\n");
    printf("  CSVs written to results/. Done.\n");
    printf("================================================================\n");
    return 0;
}
