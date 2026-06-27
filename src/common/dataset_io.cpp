#include "dataset_io.hpp"

#include <cstdint>
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace {

void write_int32_le(std::ofstream& out, int32_t value) {
    auto raw = static_cast<uint32_t>(value);
    unsigned char bytes[4] = {
        static_cast<unsigned char>(raw & 0xff),
        static_cast<unsigned char>((raw >> 8) & 0xff),
        static_cast<unsigned char>((raw >> 16) & 0xff),
        static_cast<unsigned char>((raw >> 24) & 0xff),
    };
    out.write(reinterpret_cast<const char*>(bytes), sizeof(bytes));
}

int32_t read_int32_le(std::ifstream& in) {
    unsigned char bytes[4];
    in.read(reinterpret_cast<char*>(bytes), sizeof(bytes));
    if (!in) {
        throw std::runtime_error("unexpected end of file while reading int32");
    }
    uint32_t raw = static_cast<uint32_t>(bytes[0])
        | (static_cast<uint32_t>(bytes[1]) << 8)
        | (static_cast<uint32_t>(bytes[2]) << 16)
        | (static_cast<uint32_t>(bytes[3]) << 24);
    return static_cast<int32_t>(raw);
}

std::string join_path(const std::string& dir, const std::string& name) {
    if (dir.empty()) {
        return name;
    }
    if (dir.back() == '/') {
        return dir + name;
    }
    return dir + "/" + name;
}

}  // namespace

void write_dataset(const std::string& dir, const Dataset& dataset,
                   const std::vector<unsigned char>& expected_digests) {
    if (dataset.num_messages != static_cast<int>(dataset.offsets.size())
        || dataset.num_messages != static_cast<int>(dataset.lengths.size())) {
        throw std::invalid_argument("dataset field sizes do not match num_messages");
    }
    const std::size_t expected_bytes = static_cast<std::size_t>(dataset.num_messages) * 32U;
    if (expected_digests.size() != expected_bytes) {
        throw std::invalid_argument("expected_digests size must be num_messages * 32");
    }

    {
        std::ofstream out(join_path(dir, "messages.bin"), std::ios::binary);
        out.write(reinterpret_cast<const char*>(dataset.messages.data()),
                  static_cast<std::streamsize>(dataset.messages.size()));
    }
    {
        std::ofstream out(join_path(dir, "offsets.bin"), std::ios::binary);
        for (int offset : dataset.offsets) {
            write_int32_le(out, offset);
        }
    }
    {
        std::ofstream out(join_path(dir, "lengths.bin"), std::ios::binary);
        for (int length : dataset.lengths) {
            write_int32_le(out, length);
        }
    }
    {
        std::ofstream out(join_path(dir, "meta.txt"));
        out << "num_messages=" << dataset.num_messages << '\n';
    }
    write_digests(join_path(dir, "expected_digests.bin"), expected_digests);
}

Dataset read_dataset(const std::string& dir) {
    Dataset dataset;

    {
        std::ifstream in(join_path(dir, "meta.txt"));
        if (!in) {
            throw std::runtime_error("failed to open meta.txt");
        }
        std::string line;
        std::getline(in, line);
        const std::string prefix = "num_messages=";
        if (line.rfind(prefix, 0) != 0) {
            throw std::runtime_error("meta.txt must contain num_messages=<N>");
        }
        dataset.num_messages = std::stoi(line.substr(prefix.size()));
    }

    {
        std::ifstream in(join_path(dir, "messages.bin"), std::ios::binary | std::ios::ate);
        if (!in) {
            throw std::runtime_error("failed to open messages.bin");
        }
        const auto size = in.tellg();
        in.seekg(0);
        dataset.messages.resize(static_cast<std::size_t>(size));
        in.read(reinterpret_cast<char*>(dataset.messages.data()), size);
    }

    dataset.offsets.resize(static_cast<std::size_t>(dataset.num_messages));
    dataset.lengths.resize(static_cast<std::size_t>(dataset.num_messages));

    {
        std::ifstream in(join_path(dir, "offsets.bin"), std::ios::binary);
        for (int i = 0; i < dataset.num_messages; ++i) {
            dataset.offsets[static_cast<std::size_t>(i)] = read_int32_le(in);
        }
    }
    {
        std::ifstream in(join_path(dir, "lengths.bin"), std::ios::binary);
        for (int i = 0; i < dataset.num_messages; ++i) {
            dataset.lengths[static_cast<std::size_t>(i)] = read_int32_le(in);
        }
    }

    return dataset;
}

std::vector<unsigned char> read_digests(const std::string& path) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) {
        throw std::runtime_error("failed to open digest file: " + path);
    }
    const auto size = in.tellg();
    in.seekg(0);
    std::vector<unsigned char> digests(static_cast<std::size_t>(size));
    in.read(reinterpret_cast<char*>(digests.data()), size);
    return digests;
}

void write_digests(const std::string& path, const std::vector<unsigned char>& digests) {
    std::ofstream out(path, std::ios::binary);
    out.write(reinterpret_cast<const char*>(digests.data()),
              static_cast<std::streamsize>(digests.size()));
}
