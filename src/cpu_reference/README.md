# CPU Reference — Karan Kapoor (G25AIT1233)

**Status:** stub — implement `cpu_reference.cpp`

## Build

```bash
make cpu_reference
```

## Run

```bash
./build/cpu_reference <num_messages> <data_dir>
```

## Deliverables

- OpenSSL SHA-256 reference for each message
- Writes `messages.bin`, `offsets.bin`, `lengths.bin`, `meta.txt`, `expected_digests.bin`
- NIST test vectors (`""`, `"abc"`, 56-byte string) embedded at front

See [IO_CONTRACT.md](../../IO_CONTRACT.md) §4–§5.
