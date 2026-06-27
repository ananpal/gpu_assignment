# src/cpu_reference — CPU reference & dataset generator

**Owner:** Karan · **Status:** Python prototype done; C++ port pending

Generates the synthetic dataset and the trusted CPU digests that everything is checked against.

## Files
- `generate_dataset.py` — Python prototype (shows the exact logic + file layout).
- `cpu_reference.cpp` — *(to build)* C++/OpenSSL port. Same output, same format.

## Build & run
```
# prototype:
python generate_dataset.py 1000000

# C++ (target):
apt-get install -y libssl-dev
g++ cpu_reference.cpp -o cpu_reference -lssl -lcrypto
./cpu_reference 1000000
```

## Output (writes to ../../data/ per IO_CONTRACT §4)
`messages.bin`, `offsets.bin`, `lengths.bin`, `expected_digests.bin`, `meta.txt`

## Notes for anyone covering this
- Keep the file format **byte-identical** to the contract — the kernel/validator depend on it.
- NIST vectors go at the front as a correctness gate.
