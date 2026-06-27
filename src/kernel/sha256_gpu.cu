#include <iostream>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <data_dir>\n";
        return 1;
    }
    std::cerr << "sha256_gpu: not implemented yet (owner: Anand Pal)\n";
    return 1;
}
