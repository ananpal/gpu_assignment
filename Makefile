CXX ?= g++
NVCC ?= nvcc
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Iinclude
NVCCFLAGS ?= -std=c++17 -Iinclude
LDFLAGS_SSL ?= -lssl -lcrypto

BUILD_DIR := build
COMMON_SRC := src/common/dataset_io.cpp
COMMON_OBJ := $(BUILD_DIR)/dataset_io.o

.PHONY: all clean cpu_reference kernel validate benchmark

all: cpu_reference kernel validate benchmark

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(COMMON_OBJ): $(COMMON_SRC) include/dataset_io.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c $< -o $@

cpu_reference: $(BUILD_DIR)/cpu_reference
$(BUILD_DIR)/cpu_reference: src/cpu_reference/cpu_reference.cpp $(COMMON_OBJ) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@ $(LDFLAGS_SSL)

validate: $(BUILD_DIR)/validate
$(BUILD_DIR)/validate: src/validate/validate.cpp $(COMMON_OBJ) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $^ -o $@

kernel: $(BUILD_DIR)/sha256_gpu
$(BUILD_DIR)/sha256_gpu: src/kernel/sha256_gpu.cu $(COMMON_OBJ) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< $(COMMON_OBJ) -o $@

benchmark: $(BUILD_DIR)/benchmark
$(BUILD_DIR)/benchmark: src/benchmark/benchmark.cu $(COMMON_OBJ) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< $(COMMON_OBJ) -o $@

clean:
	rm -rf $(BUILD_DIR)
