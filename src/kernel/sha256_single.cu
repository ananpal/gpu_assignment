// =====================================================================
// sha256_single.cu  —  Stage A+B: hash ONE message on the GPU
//
// Goal: prove the SHA-256 math is correct on the GPU for a single message.
// Once this prints the right hash for "abc", you KNOW the math works, and
// Stage C is just "run this per message across many threads."
//
// Build:  !nvcc sha256_single.cu -o sha256_single
// Run:    !./sha256_single
// Expect: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
// =====================================================================
#include <cstdio>
#include <cstring>

// ---------------------------------------------------------------------
// SHA-256 constants. The assignment asks for these in CONSTANT MEMORY,
// so all threads read them from the GPU's fast read-only cache.
// These 64 values are fixed by the standard — copied, never invented.
// ---------------------------------------------------------------------
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

// ---------------------------------------------------------------------
// The SHA-256 bit-mixing operations, as macros. These are the exact
// formulas from the standard. ROTR = rotate-right (bits that fall off
// the right wrap around to the left).
// ---------------------------------------------------------------------
#define ROTR(x,n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)     (ROTR(x,2)  ^ ROTR(x,13) ^ ROTR(x,22))
#define EP1(x)     (ROTR(x,6)  ^ ROTR(x,11) ^ ROTR(x,25))
#define SIG0(x)    (ROTR(x,7)  ^ ROTR(x,18) ^ ((x) >> 3))
#define SIG1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

// ---------------------------------------------------------------------
// Process ONE 64-byte block, updating the 8 hash words in h[].
// This is the heart of SHA-256: build a 64-word schedule, then 64 rounds.
// ---------------------------------------------------------------------
__device__ void sha256_transform(unsigned int h[8], const unsigned char* block) {
    unsigned int w[64];

    // 1. First 16 words come straight from the block (big-endian).
    for (int i = 0; i < 16; i++)
        w[i] = (block[i*4] << 24) | (block[i*4+1] << 16) |
               (block[i*4+2] << 8) |  block[i*4+3];

    // 2. Remaining 48 words are mixed from earlier ones.
    for (int i = 16; i < 64; i++)
        w[i] = SIG1(w[i-2]) + w[i-7] + SIG0(w[i-15]) + w[i-16];

    // 3. Init working variables from current hash state.
    unsigned int a=h[0], b=h[1], c=h[2], d=h[3], e=h[4], f=h[5], g=h[6], hh=h[7];

    // 4. The 64 rounds of mixing.
    for (int i = 0; i < 64; i++) {
        unsigned int t1 = hh + EP1(e) + CH(e,f,g) + K[i] + w[i];
        unsigned int t2 = EP0(a) + MAJ(a,b,c);
        hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
    }

    // 5. Add the result back into the hash state.
    h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
}

// ---------------------------------------------------------------------
// Hash one message of arbitrary length -> 32-byte digest in out[].
// Handles padding (append 0x80, zeros, then the 64-bit length).
// ---------------------------------------------------------------------
__device__ void sha256_hash(const unsigned char* data, unsigned int len, unsigned char* out) {
    // Standard SHA-256 starting hash values.
    unsigned int h[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };

    // Process every COMPLETE 64-byte block directly from the input.
    unsigned int i = 0;
    while (len - i >= 64) {
        sha256_transform(h, data + i);
        i += 64;
    }

    // Build the final padded block(s) in a small local buffer.
    // (Padding may spill into a second block, so we allow up to 128 bytes.)
    unsigned char buf[128];
    unsigned int rem = len - i;                 // leftover bytes (< 64)
    for (unsigned int j = 0; j < rem; j++) buf[j] = data[i + j];
    buf[rem] = 0x80;                            // the mandatory '1' bit then zeros

    unsigned int total = (rem < 56) ? 64 : 128; // need room for the 8-byte length
    for (unsigned int j = rem + 1; j < total - 8; j++) buf[j] = 0;

    // Append the original length in BITS, as a 64-bit big-endian number.
    unsigned long long bitlen = (unsigned long long)len * 8;
    for (int j = 0; j < 8; j++)
        buf[total - 1 - j] = (unsigned char)((bitlen >> (8 * j)) & 0xff);

    sha256_transform(h, buf);
    if (total == 128) sha256_transform(h, buf + 64);

    // Write the 8 hash words out as 32 big-endian bytes.
    for (int j = 0; j < 8; j++) {
        out[j*4]   = (h[j] >> 24) & 0xff;
        out[j*4+1] = (h[j] >> 16) & 0xff;
        out[j*4+2] = (h[j] >> 8)  & 0xff;
        out[j*4+3] =  h[j]        & 0xff;
    }
}

// ---------------------------------------------------------------------
// THE KERNEL. For Stage A+B, only ONE thread does the work (one message).
// In Stage C you'll change this so thread i hashes message i.
// ---------------------------------------------------------------------
__global__ void sha256_kernel(const unsigned char* msg, unsigned int len, unsigned char* out) {
    int id = threadIdx.x + blockIdx.x * blockDim.x;
    if (id == 0)                      // just the first thread, for now
        sha256_hash(msg, len, out);
}

// ---------------------------------------------------------------------
// HOST (CPU) side: copy "abc" to the GPU, hash it, print the result.
// ---------------------------------------------------------------------
int main() {
    const char* text = "abc";
    unsigned int len = (unsigned int)strlen(text);

    unsigned char *d_msg, *d_out;
    cudaMalloc(&d_msg, len);
    cudaMalloc(&d_out, 32);
    cudaMemcpy(d_msg, text, len, cudaMemcpyHostToDevice);

    sha256_kernel<<<1, 1>>>(d_msg, len, d_out);   // one block, one thread
    cudaDeviceSynchronize();
    printf("kernel status: %s\n", cudaGetErrorString(cudaGetLastError()));

    unsigned char h_out[32];
    cudaMemcpy(h_out, d_out, 32, cudaMemcpyDeviceToHost);

    printf("sha256(\"abc\") = ");
    for (int i = 0; i < 32; i++) printf("%02x", h_out[i]);
    printf("\n");
    printf("expected      = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n");

    cudaFree(d_msg);
    cudaFree(d_out);
    return 0;
}
