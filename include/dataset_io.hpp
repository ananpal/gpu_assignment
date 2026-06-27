#pragma once

#include <string>
#include <vector>

// Packed message dataset — see IO_CONTRACT.md §2 and §4.
struct Dataset {
    std::vector<unsigned char> messages;
    std::vector<int> offsets;
    std::vector<int> lengths;
    int num_messages = 0;
};

// Write messages.bin, offsets.bin, lengths.bin, meta.txt, expected_digests.bin
void write_dataset(const std::string& dir, const Dataset& dataset,
                   const std::vector<unsigned char>& expected_digests);

// Read messages.bin, offsets.bin, lengths.bin, meta.txt
Dataset read_dataset(const std::string& dir);

// Read a flat digest file (expected_digests.bin or gpu_digests.bin)
std::vector<unsigned char> read_digests(const std::string& path);

// Write gpu_digests.bin (same layout as expected_digests.bin)
void write_digests(const std::string& path, const std::vector<unsigned char>& digests);
