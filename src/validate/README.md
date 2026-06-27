# Validator — Arundhati (G25AIT1033)

**Status:** stub — implement `validate.cpp`

## Build

```bash
make validate
```

## Run

```bash
./build/validate <data_dir>
```

## Deliverables

- Compare `gpu_digests.bin` vs `expected_digests.bin` slot-by-slot
- Report first mismatch; print `ALL MATCH` on success
- Edge-case suite: lengths 0, 1, 55, 56, 64 bytes

See [IO_CONTRACT.md](../../IO_CONTRACT.md) §4–§6.
