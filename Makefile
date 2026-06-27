# GPU SHA-256 — Group 29 build system

CXX      ?= g++
NVCC     ?= nvcc
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Iinclude
NVCCFLAGS ?= -std=c++17 -Iinclude
LDFLAGS_SSL ?= -lssl -lcrypto

BUILD_DIR := build
DATA_DIR  ?= data

CPU_REF_SRC    := src/cpu_reference/cpu_reference.cpp
KERNEL_SRC     := src/kernel/sha256_gpu.cu
VALIDATE_SRC   := src/validate/validate.cpp
BENCHMARK_SRC  := src/benchmark/benchmark.cu
SHA256_CUH     := include/sha256.cuh
DATASET_IO_HPP := include/dataset_io.hpp
DATASET_IO_CPP := src/common/dataset_io.cpp
RUN_ALL        := scripts/run_all.sh

DATA_FILES := messages.bin offsets.bin lengths.bin meta.txt expected_digests.bin gpu_digests.bin

.PHONY: all help status pipeline clean \
        cpu_reference kernel validate benchmark run \
        build-system

.DEFAULT_GOAL := help

help:
	@echo "================================================================"
	@echo "  GPU SHA-256 — Makefile | Group 29"
	@echo "================================================================"
	@echo ""
	@echo "Targets:"
	@echo "  make help           This message"
	@echo "  make status         Task checklist + which files are missing"
	@echo "  make pipeline       Pipeline order + expected output per step"
	@echo "  make build-system   Build-system + benchmark + report tasks"
	@echo "  make cpu_reference  CPU reference + dataset generator"
	@echo "  make kernel         CUDA SHA-256 kernel"
	@echo "  make validate       Correctness validation"
	@echo "  make benchmark      Throughput benchmark harness"
	@echo "  make all            Build every module with source present"
	@echo "  make run N=1000     Run pipeline (after all modules exist)"
	@echo "  make clean          Remove $(BUILD_DIR)/"
	@echo ""
	@echo "Quick check:  make status"

status:
	@echo "================================================================"
	@echo "  PROJECT STATUS — required files vs present"
	@echo "================================================================"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(SHA256_CUH)" TASK="I/O contract + device SHA-256 helpers"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(KERNEL_SRC)" TASK="CUDA kernel; write gpu_digests.bin"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(CPU_REF_SRC)" TASK="OpenSSL dataset generator + CPU reference"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(VALIDATE_SRC)" TASK="memcmp gpu_digests vs expected_digests"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(BENCHMARK_SRC)" TASK="CUDA event timing; hashes/sec; GB/s"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(DATASET_IO_HPP)" TASK="shared: dataset struct + read/write declarations"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(DATASET_IO_CPP)" TASK="shared (optional): dataset .bin I/O implementation"
	@echo ""
	@echo "--- data/ artifacts (generated at runtime, not committed) ---"
	@for f in $(DATA_FILES); do \
		if [ -f "$(DATA_DIR)/$$f" ]; then echo "  [ok]   $(DATA_DIR)/$$f"; \
		else echo "  [----] $(DATA_DIR)/$$f"; fi; \
	done
	@echo ""
	@echo "--- large-scale GPU runs ---"
	@echo "  Task: repo setup, results/ logs, charts, GPU specs"
	@echo "  Run:  make run N=1000000  (after ALL MATCH on small data)"

pipeline:
	@echo "================================================================"
	@echo "  PIPELINE (run in this order)"
	@echo "================================================================"
	@echo ""
	@echo "Step 1 — CPU reference + dataset generator"
	@echo "  Command:  make cpu_reference"
	@echo "            ./$(BUILD_DIR)/cpu_reference <N> $(DATA_DIR)/"
	@echo "  Needs:    $(CPU_REF_SRC)"
	@echo "            $(DATASET_IO_HPP) [+ $(DATASET_IO_CPP) if used]"
	@echo "  Creates:  $(DATA_DIR)/messages.bin"
	@echo "            $(DATA_DIR)/offsets.bin"
	@echo "            $(DATA_DIR)/lengths.bin"
	@echo "            $(DATA_DIR)/meta.txt"
	@echo "            $(DATA_DIR)/expected_digests.bin"
	@echo "  Expected: NIST asserts pass; prints num_messages=<N>"
	@echo ""
	@echo "Step 2 — CUDA SHA-256 kernel"
	@echo "  Command:  make kernel"
	@echo "            ./$(BUILD_DIR)/sha256_gpu $(DATA_DIR)/"
	@echo "  Needs:    $(KERNEL_SRC)"
	@echo "            $(SHA256_CUH)"
	@echo "            $(DATASET_IO_HPP) [+ $(DATASET_IO_CPP) if used]"
	@echo "            $(DATA_DIR)/messages.bin ... expected_digests.bin (from step 1)"
	@echo "  Creates:  $(DATA_DIR)/gpu_digests.bin"
	@echo "  Expected: kernel completes without CUDA errors"
	@echo ""
	@echo "Step 3 — Correctness validation"
	@echo "  Command:  make validate"
	@echo "            ./$(BUILD_DIR)/validate $(DATA_DIR)/"
	@echo "  Needs:    $(VALIDATE_SRC)"
	@echo "            $(DATA_DIR)/gpu_digests.bin"
	@echo "            $(DATA_DIR)/expected_digests.bin"
	@echo "  Expected: ALL MATCH  (or first mismatch index + hex digests)"
	@echo ""
	@echo "Step 4 — Throughput benchmark"
	@echo "  Command:  make benchmark"
	@echo "            ./$(BUILD_DIR)/benchmark $(DATA_DIR)/"
	@echo "  Needs:    $(BENCHMARK_SRC)"
	@echo "            $(SHA256_CUH)  (same hash math as kernel)"
	@echo "            full dataset in $(DATA_DIR)/"
	@echo "  Expected: hashes/sec, GB/s (with and without H<->D transfer)"
	@echo "            CPU OpenSSL baseline timing for comparison"
	@echo ""
	@echo "Step 5 — Large-scale runs on GPU machine"
	@echo "  Command:  make run N=1000000"
	@echo "  Expected: ALL MATCH at 1M–10M; results saved under results/"

build-system:
	@echo "================================================================"
	@echo "  Build system + benchmark + report tasks"
	@echo "================================================================"
	@echo "  Tasks:"
	@echo "    1. Maintain this Makefile (build all modules + status)"
	@echo "    2. Implement $(BENCHMARK_SRC)"
	@echo "    3. Assemble docs/report/ (intro + security note)"
	@echo ""
	@echo "  Files:"
	@echo "    - Makefile"
	@echo "    - $(BENCHMARK_SRC)"
	@echo "    - docs/report/"
	@echo "    - $(RUN_ALL)  (optional: end-to-end runner)"
	@echo ""
	@echo "  Done when:"
	@echo "    make benchmark  -> builds $(BUILD_DIR)/benchmark"
	@echo "    ./build/benchmark data/  -> prints GPU vs CPU timing table"
	@echo "    make all        -> builds every implemented module"

all: cpu_reference kernel validate benchmark
	@echo ""
	@echo "All present modules built under $(BUILD_DIR)/"

cpu_reference: $(BUILD_DIR)/cpu_reference

kernel: $(BUILD_DIR)/sha256_gpu

validate: $(BUILD_DIR)/validate

benchmark: $(BUILD_DIR)/benchmark

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/cpu_reference: $(CPU_REF_SRC) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS_SSL)

$(BUILD_DIR)/sha256_gpu: $(KERNEL_SRC) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< -o $@

$(BUILD_DIR)/validate: $(VALIDATE_SRC) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $< -o $@

$(BUILD_DIR)/benchmark: $(BENCHMARK_SRC) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< -o $@

$(CPU_REF_SRC):
	@$(MAKE) --no-print-directory _missing \
		TASKS="OpenSSL SHA-256 reference, NIST vectors, write .bin dataset" \
		FILE="$@" \
		OUTPUT="./$(BUILD_DIR)/cpu_reference <N> $(DATA_DIR)/ -> messages.bin, offsets.bin, lengths.bin, meta.txt, expected_digests.bin"
	@false

$(KERNEL_SRC):
	@$(MAKE) --no-print-directory _missing \
		TASKS="CUDA sha256_kernel, load dataset, write gpu_digests.bin" \
		FILE="$@" \
		OUTPUT="./$(BUILD_DIR)/sha256_gpu $(DATA_DIR)/ -> gpu_digests.bin"
	@false

$(VALIDATE_SRC):
	@$(MAKE) --no-print-directory _missing \
		TASKS="slot-by-slot memcmp, edge cases, print ALL MATCH" \
		FILE="$@" \
		OUTPUT="./$(BUILD_DIR)/validate $(DATA_DIR)/ -> ALL MATCH"
	@false

$(BENCHMARK_SRC):
	@$(MAKE) --no-print-directory _missing \
		TASKS="CUDA event timers, hashes/sec, GB/s, CPU baseline" \
		FILE="$@" \
		OUTPUT="./$(BUILD_DIR)/benchmark $(DATA_DIR)/ -> timing table"
	@false

N ?= 1000
run: all
	@mkdir -p $(DATA_DIR) results
	@echo "==> Step 1/4: cpu_reference ($(N) messages)"
	./$(BUILD_DIR)/cpu_reference $(N) $(DATA_DIR)/
	@echo "==> Step 2/4: kernel"
	./$(BUILD_DIR)/sha256_gpu $(DATA_DIR)/
	@echo "==> Step 3/4: validate"
	./$(BUILD_DIR)/validate $(DATA_DIR)/
	@echo "==> Step 4/4: benchmark"
	./$(BUILD_DIR)/benchmark $(DATA_DIR)/
	@echo "Pipeline complete."

clean:
	rm -rf $(BUILD_DIR)

_check_file:
	@if [ -f "$(FILE)" ]; then \
		echo "  [ok]   $(FILE)  — $(TASK)"; \
	else \
		echo "  [MISS] $(FILE)  — $(TASK)"; \
	fi

_missing:
	@echo ""
	@echo "----------------------------------------------------------------"
	@echo "  MISSING: $(FILE)"
	@echo "  Tasks:   $(TASKS)"
	@echo "  Expected output when implemented:"
	@echo "    $(OUTPUT)"
	@echo "----------------------------------------------------------------"
	@echo "  See: IO_CONTRACT.md, TASKS.md, make pipeline"
	@echo ""
