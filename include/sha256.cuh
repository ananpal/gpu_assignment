// =====================================================================
// sha256.cuh — shared SHA-256 device code (constants, macros, device
// functions, kernel). Include this from a single .cu program.
//
// Used by: src/kernel/sha256_gpu.cu (and later src/benchmark/benchmark.cu).
// The hash math is verified against the NIST vectors (empty, "abc",
// the 56-byte string, multi-block).
// =====================================================================
#pragma once

// SHA-256 round constants, in GPU constant memory (fast, read-only, shared
// by all threads). Defined here; include this header in exactly ONE .cu per
// compiled program so there is a single definition.
__constant__ unsigned int K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

#define ROTR(x,n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)     (ROTR(x,2)  ^ ROTR(x,13) ^ ROTR(x,22))
#define EP1(x)     (ROTR(x,6)  ^ ROTR(x,11) ^ ROTR(x,25))
#define SIG0(x)    (ROTR(x,7)  ^ ROTR(x,18) ^ ((x) >> 3))
#define SIG1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

__device__ inline void sha256_transform(unsigned int h[8], const unsigned char* block) {
    unsigned int w[64];
    for (int i = 0; i < 16; i++)
        w[i] = ((unsigned int)block[i*4] << 24) | ((unsigned int)block[i*4+1] << 16) |
               ((unsigned int)block[i*4+2] << 8) |  (unsigned int)block[i*4+3];
    for (int i = 16; i < 64; i++)
        w[i] = SIG1(w[i-2]) + w[i-7] + SIG0(w[i-15]) + w[i-16];

    unsigned int a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], hh=h[7];
    for (int i = 0; i < 64; i++) {
        unsigned int t1 = hh + EP1(e) + CH(e,f,g) + K[i] + w[i];
        unsigned int t2 = EP0(a) + MAJ(a,b,c);
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }
    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}

__device__ inline void sha256_hash(const unsigned char* data, unsigned int length, unsigned char* result) {
    unsigned int h[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };
    unsigned int i = 0;
    while (length - i >= 64) { sha256_transform(h, data + i); i += 64; }

    unsigned char buf[128];
    unsigned int rem = length - i;
    for (unsigned int j = 0; j < rem; j++) buf[j] = data[i + j];
    buf[rem] = 0x80;
    unsigned int total = (rem < 56) ? 64 : 128;
    for (unsigned int j = rem + 1; j < total - 8; j++) buf[j] = 0;
    unsigned long long bitlen = (unsigned long long)length * 8;
    for (int j = 0; j < 8; j++)
        buf[total - 1 - j] = (unsigned char)((bitlen >> (8 * j)) & 0xff);
    sha256_transform(h, buf);
    if (total == 128) sha256_transform(h, buf + 64);

    for (int j = 0; j < 8; j++) {
        result[j*4]   = (h[j] >> 24) & 0xff;
        result[j*4+1] = (h[j] >> 16) & 0xff;
        result[j*4+2] = (h[j] >> 8)  & 0xff;
        result[j*4+3] =  h[j]        & 0xff;
    }
}

// Thread i hashes message i and writes its 32-byte digest to digests[i*32].
// (size_t)i * 32 keeps the output offset 64-bit so it stays correct past ~67M messages.
__global__ inline void sha256_kernel(const unsigned char* messages, const int* offsets,
                                     const int* lengths, unsigned char* digests, int num_messages) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i < num_messages) {
        sha256_hash(messages + offsets[i], (unsigned int)lengths[i], digests + (size_t)i * 32);
    }
}
