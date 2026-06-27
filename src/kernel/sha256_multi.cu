// =====================================================================
// sha256_multi.cu  —  Stage C: hash MANY messages in parallel
//
// Thread i hashes message i (the I/O contract model). This is the real
// deliverable. The device functions (transform/hash) are UNCHANGED from
// sha256_single.cu — only the kernel and host code are different.
//
// Build:  !nvcc sha256_multi.cu -o sha256_multi
// Run:    !./sha256_multi
// =====================================================================
#include <cstdio>
#include <cstring>

// ---------------------------------------------------------------------
// Constants in constant memory (unchanged).
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

#define ROTR(x,n)  (((x) >> (n)) | ((x) << (32 - (n))))
#define CH(x,y,z)  (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x)     (ROTR(x,2)  ^ ROTR(x,13) ^ ROTR(x,22))
#define EP1(x)     (ROTR(x,6)  ^ ROTR(x,11) ^ ROTR(x,25))
#define SIG0(x)    (ROTR(x,7)  ^ ROTR(x,18) ^ ((x) >> 3))
#define SIG1(x)    (ROTR(x,17) ^ ROTR(x,19) ^ ((x) >> 10))

// ---------------------------------------------------------------------
// Device functions (UNCHANGED from the single-message version).
// ---------------------------------------------------------------------
__device__ void sha256_transform(unsigned int h[8], const unsigned char* block) {
    unsigned int w[64];
    for (int i = 0; i < 16; i++)
        w[i] = (block[i*4] << 24) | (block[i*4+1] << 16) |
               (block[i*4+2] << 8) |  block[i*4+3];
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

__device__ void sha256_hash(const unsigned char* data, unsigned int len, unsigned char* out) {
    unsigned int h[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };
    unsigned int i = 0;
    while (len - i >= 64) { sha256_transform(h, data + i); i += 64; }

    unsigned char buf[128];
    unsigned int rem = len - i;
    for (unsigned int j = 0; j < rem; j++) buf[j] = data[i + j];
    buf[rem] = 0x80;
    unsigned int total = (rem < 56) ? 64 : 128;
    for (unsigned int j = rem + 1; j < total - 8; j++) buf[j] = 0;
    unsigned long long bitlen = (unsigned long long)len * 8;
    for (int j = 0; j < 8; j++)
        buf[total - 1 - j] = (unsigned char)((bitlen >> (8 * j)) & 0xff);
    sha256_transform(h, buf);
    if (total == 128) sha256_transform(h, buf + 64);

    for (int j = 0; j < 8; j++) {
        out[j*4]   = (h[j] >> 24) & 0xff;
        out[j*4+1] = (h[j] >> 16) & 0xff;
        out[j*4+2] = (h[j] >> 8)  & 0xff;
        out[j*4+3] =  h[j]        & 0xff;
    }
}

// ---------------------------------------------------------------------
// THE STAGE-C KERNEL: thread i hashes message i.
// This is the only conceptually new code vs. the single-message version.
// ---------------------------------------------------------------------
__global__ void sha256_kernel(const unsigned char* messages, const int* offsets,
                              const int* lengths, unsigned char* digests, int num_messages) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;   // which message is mine?
    if (i < num_messages) {                          // skip out-of-range threads
        // my message starts at offsets[i] and is lengths[i] bytes long;
        // my 32-byte digest goes at digests[i*32].
        sha256_hash(messages + offsets[i], (unsigned int)lengths[i], digests + i * 32);
    }
}

// ---------------------------------------------------------------------
// HOST (CPU) side.
// ---------------------------------------------------------------------
int main() {
    // 1. Test messages (note the empty string and a 56-byte one that
    //    forces padding into a SECOND block — good edge cases).
    const char* msgs[] = {
        "abc",
        "hello",
        "",
        "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    };
    const char* expected[] = {
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
        "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
    };
    int num_messages = 4;

    // 2. Pack messages into one buffer + build offsets/lengths (the I/O contract).
    int h_lengths[4], h_offsets[4];
    int total_bytes = 0;
    for (int i = 0; i < num_messages; i++) {
        h_lengths[i] = (int)strlen(msgs[i]);
        h_offsets[i] = total_bytes;
        total_bytes += h_lengths[i];
    }
    unsigned char* h_messages = (unsigned char*)malloc(total_bytes);
    for (int i = 0; i < num_messages; i++)
        memcpy(h_messages + h_offsets[i], msgs[i], h_lengths[i]);

    // 3. Allocate GPU memory and copy inputs over.
    unsigned char *d_messages, *d_digests;
    int *d_offsets, *d_lengths;
    cudaMalloc(&d_messages, total_bytes);
    cudaMalloc(&d_offsets,  num_messages * sizeof(int));
    cudaMalloc(&d_lengths,  num_messages * sizeof(int));
    cudaMalloc(&d_digests,  num_messages * 32);

    cudaMemcpy(d_messages, h_messages, total_bytes,               cudaMemcpyHostToDevice);
    cudaMemcpy(d_offsets,  h_offsets,  num_messages*sizeof(int),  cudaMemcpyHostToDevice);
    cudaMemcpy(d_lengths,  h_lengths,  num_messages*sizeof(int),  cudaMemcpyHostToDevice);

    // 4. Launch: one thread per message (round-up block count).
    int threadsPerBlock = 256;
    int numBlocks = (num_messages + threadsPerBlock - 1) / threadsPerBlock;
    sha256_kernel<<<numBlocks, threadsPerBlock>>>(d_messages, d_offsets, d_lengths,
                                                  d_digests, num_messages);
    cudaDeviceSynchronize();
    printf("kernel status: %s\n\n", cudaGetErrorString(cudaGetLastError()));

    // 5. Copy digests back and check each against the expected hash.
    unsigned char* h_digests = (unsigned char*)malloc(num_messages * 32);
    cudaMemcpy(h_digests, d_digests, num_messages * 32, cudaMemcpyDeviceToHost);

    int all_ok = 1;
    for (int i = 0; i < num_messages; i++) {
        char hex[65];
        for (int j = 0; j < 32; j++) sprintf(hex + j*2, "%02x", h_digests[i*32 + j]);
        int ok = (strcmp(hex, expected[i]) == 0);
        if (!ok) all_ok = 0;
        printf("msg %d (\"%s\")\n  got: %s\n  exp: %s  [%s]\n\n",
               i, msgs[i], hex, expected[i], ok ? "PASS" : "FAIL");
    }
    printf(all_ok ? "ALL PASS\n" : "SOME FAILED\n");

    // 6. Cleanup.
    free(h_messages); free(h_digests);
    cudaFree(d_messages); cudaFree(d_offsets); cudaFree(d_lengths); cudaFree(d_digests);
    return 0;
}
