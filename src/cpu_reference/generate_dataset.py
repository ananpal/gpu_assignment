#!/usr/bin/env python3
# =====================================================================
# generate_dataset.py  —  Member 2's deliverable
#
# Does all three parts of M2's task:
#   1. CPU reference baseline  -> Python's hashlib (the trusted SHA-256)
#   2. NIST / known test vectors -> verified, and embedded at the front
#   3. Large synthetic dataset -> millions of messages + their digests
#
# Writes files in the I/O-contract (§4) format that M3's kernel reads:
#   data/messages.bin          all messages packed back-to-back
#   data/offsets.bin           int32: start byte of each message
#   data/lengths.bin           int32: byte length of each message
#   data/expected_digests.bin  the CPU reference: 32 bytes per message
#   data/meta.txt              num_messages=<N>
#
# Usage:
#   python generate_dataset.py            # default 1,000,000 messages
#   python generate_dataset.py 10000000   # 10 million
# =====================================================================
import hashlib
import os
import sys
import numpy as np

OUTDIR = "data"

# ---------------------------------------------------------------------
# PART 2: Official NIST / known-answer test vectors.
# These are published by the standard, so they're an INDEPENDENT check:
# if both hashlib and the GPU match these, correctness is proven.
# We verify them, then put them at the START of the dataset so the GPU's
# digests[0..2] also have known-correct answers.
# ---------------------------------------------------------------------
NIST_VECTORS = [
    (b"", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    (b"abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"),
    (b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
     "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"),
]

def verify_nist():
    """PART 1+2: confirm our CPU baseline (hashlib) matches the NIST answers."""
    print("Verifying NIST test vectors against hashlib...")
    for msg, expected in NIST_VECTORS:
        got = hashlib.sha256(msg).hexdigest()
        assert got == expected, f"MISMATCH for {msg!r}:\n  got {got}\n  exp {expected}"
        label = repr(msg) if msg else "b'' (empty)"
        print(f"  OK  {label[:40]:<40} -> {got[:16]}...")
    print("All NIST vectors PASS.\n")

# ---------------------------------------------------------------------
# PART 3: generate N synthetic messages.
# "Synthetic" = made up; the content doesn't matter, only that there's
# a lot of it. We vary the length a little so messages aren't identical.
# ---------------------------------------------------------------------
def generate_messages(n):
    """Return a list of n byte-string messages (the NIST vectors come first)."""
    msgs = [m for m, _ in NIST_VECTORS]            # known vectors at the front
    for i in range(n - len(msgs)):
        # e.g. b"msg_00000042_padding..." with a length that varies by i
        body = f"msg_{i:09d}".encode()
        body += b"x" * (i % 40)                     # vary length 0..39 extra bytes
        msgs.append(body)
    return msgs

# ---------------------------------------------------------------------
# Pack everything and compute the CPU reference digests, then write files.
# ---------------------------------------------------------------------
def build_and_write(messages, outdir):
    num = len(messages)
    offsets = np.empty(num, dtype=np.int32)
    lengths = np.empty(num, dtype=np.int32)
    msg_buf = bytearray()       # all messages concatenated
    dig_buf = bytearray()       # all CPU-reference digests concatenated

    total = 0
    for i, m in enumerate(messages):
        offsets[i] = total
        lengths[i] = len(m)
        total += len(m)
        msg_buf += m
        dig_buf += hashlib.sha256(m).digest()   # <-- PART 1: the CPU baseline

    # int32 offsets can address up to ~2.1 GB of total message bytes.
    if total > 2_147_483_647:
        sys.exit("ERROR: total bytes exceed int32 range; switch offsets to int64 (tell M1).")

    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "messages.bin"), "wb") as f:
        f.write(msg_buf)
    offsets.tofile(os.path.join(outdir, "offsets.bin"))        # little-endian int32
    lengths.tofile(os.path.join(outdir, "lengths.bin"))
    with open(os.path.join(outdir, "expected_digests.bin"), "wb") as f:
        f.write(dig_buf)
    with open(os.path.join(outdir, "meta.txt"), "w") as f:
        f.write(f"num_messages={num}\n")

    print(f"Wrote dataset to '{outdir}/':")
    print(f"  num_messages        = {num:,}")
    print(f"  messages.bin        = {total:,} bytes")
    print(f"  expected_digests.bin= {num*32:,} bytes")
    print(f"  avg message length  = {total/num:.1f} bytes")

# ---------------------------------------------------------------------
def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
    verify_nist()
    print(f"Generating {n:,} messages (NIST vectors first)...")
    messages = generate_messages(n)
    build_and_write(messages, OUTDIR)
    print("\nDone. M3's kernel can now load these files instead of hardcoded messages.")

if __name__ == "__main__":
    main()
