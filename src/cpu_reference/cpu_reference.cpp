#include <iostream>

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <num_messages> <data_dir>\n";
        return 1;
    }
    std::cerr << "cpu_reference: not implemented yet (owner: Karan Kapoor)\n";
    return 1;
}
