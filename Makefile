# GPU SHA-256 build system (Mohshinsha / G25AIT1093)

CXX      ?= g++
NVCC     ?= nvcc
CXXFLAGS ?= -std=c++17 -Wall -Wextra -Iinclude
NVCCFLAGS ?= -std=c++17 -Iinclude
LDFLAGS_SSL ?= -lssl -lcrypto

BUILD_DIR := build
DATA_DIR  ?= data

SMOKE_SRC      := src/kernel/sha256_smoke_test.cu
CPU_REF_SRC    := src/cpu_reference/cpu_reference.cpp
HASH_DATASET_SRC := src/kernel/hash_dataset.cu
KERNEL_SRC     := src/kernel/sha256_gpu.cu
VALIDATE_SRC   := src/validate/validate.cpp
BENCHMARK_SRC  := src/benchmark/benchmark.cu
SHA256_CUH     := include/sha256.cuh

DATA_FILES := messages.bin offsets.bin lengths.bin meta.txt expected_digests.bin gpu_digests.bin

.PHONY: all help status pipeline run clean \
        smoke_test cpu_reference hash_dataset validate benchmark

.DEFAULT_GOAL := help

help:
	@echo "================================================================"
	@echo "  GPU SHA-256 — Makefile"
	@echo "================================================================"
	@echo ""
	@echo "Targets:"
	@echo "  make help           This message"
	@echo "  make status         Task checklist + which files are missing"
	@echo "  make pipeline       Pipeline order + expected output per step"
	@echo "  make smoke_test     Quick NIST-vector smoke test"
	@echo "  make cpu_reference  CPU reference + dataset generator"
	@echo "  make hash_dataset   GPU dataset driver -> gpu_digests.bin"
	@echo "  make validate       Correctness validation"
	@echo "  make benchmark      Throughput benchmark harness"
	@echo "  make all            Build every module"
	@echo "  make run N=100000   End-to-end pipeline"
	@echo "  make clean          Remove $(BUILD_DIR)/"
	@echo ""
	@echo "Quick check:  make status"

status:
	@echo "================================================================"
	@echo "  PROJECT STATUS — required files vs present"
	@echo "================================================================"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(SHA256_CUH)" TASK="Device SHA-256 helpers" \
		OWNER="Anand Pal (G25AIT1019)"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(KERNEL_SRC)" TASK="GPU SHA-256 engine API" \
		OWNER="Anand Pal (G25AIT1019)"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(HASH_DATASET_SRC)" TASK="Dataset driver; write gpu_digests.bin" \
		OWNER="Anand Pal (G25AIT1019)"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(CPU_REF_SRC)" TASK="OpenSSL dataset generator + CPU reference" \
		OWNER="Karan Kapoor (G25AIT1233)"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(VALIDATE_SRC)" TASK="GPU vs CPU correctness validation" \
		OWNER="Arundhati (G25AIT1033)"
	@$(MAKE) --no-print-directory _check_file \
		FILE="$(BENCHMARK_SRC)" TASK="CUDA event timing; hashes/sec; GB/s" \
		OWNER="Mohshinsha Harunsha Shahmadar (G25AIT1093)"
	@echo ""
	@echo "--- data/ artifacts (generated at runtime, not committed) ---"
	@for f in $(DATA_FILES); do \
		case "$$f" in \
			gpu_digests.bin) owner="Anand Pal (G25AIT1019)" ;; \
			*) owner="Karan Kapoor (G25AIT1233)" ;; \
		esac; \
		if [ -f "$(DATA_DIR)/$$f" ]; then echo "  [ok]   $(DATA_DIR)/$$f"; \
		else echo "  [----] $(DATA_DIR)/$$f  -> $$owner"; fi; \
	done
	@echo ""
	@echo "--- build/ binaries ---"
	@for b in smoke_test cpu_reference hash_dataset validate benchmark; do \
		if [ -f "$(BUILD_DIR)/$$b" ]; then echo "  [ok]   $(BUILD_DIR)/$$b"; \
		else echo "  [----] $(BUILD_DIR)/$$b"; fi; \
	done

pipeline:
	@echo "================================================================"
	@echo "  PIPELINE (run in this order)"
	@echo "================================================================"
	@echo ""
	@echo "Step 1 — CPU reference + dataset generator"
	@echo "  Command:  ./$(BUILD_DIR)/cpu_reference <N> $(DATA_DIR)/"
	@echo "  Creates:  $(DATA_DIR)/messages.bin, offsets.bin, lengths.bin,"
	@echo "            meta.txt, expected_digests.bin"
	@echo ""
	@echo "Step 2 — GPU hash dataset"
	@echo "  Command:  ./$(BUILD_DIR)/hash_dataset $(DATA_DIR)/"
	@echo "  Creates:  $(DATA_DIR)/gpu_digests.bin"
	@echo ""
	@echo "Step 3 — Correctness validation"
	@echo "  Command:  ./$(BUILD_DIR)/validate $(DATA_DIR)/"
	@echo "  Expected: VALIDATION PASSED / ALL MATCH"
	@echo ""
	@echo "Step 4 — Throughput benchmark"
	@echo "  Command:  ./$(BUILD_DIR)/benchmark $(DATA_DIR)/"
	@echo "  Expected: hashes/sec, GB/s (kernel-only and with H<->D transfer)"
	@echo ""
	@echo "Or run all steps:  make run N=100000"

all: smoke_test cpu_reference hash_dataset validate benchmark
	@echo ""
	@echo "All modules built under $(BUILD_DIR)/"

smoke_test: $(BUILD_DIR)/smoke_test

cpu_reference: $(BUILD_DIR)/cpu_reference

hash_dataset: $(BUILD_DIR)/hash_dataset

validate: $(BUILD_DIR)/validate

benchmark: $(BUILD_DIR)/benchmark

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/smoke_test: $(SMOKE_SRC) $(SHA256_CUH) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< -o $@

$(BUILD_DIR)/cpu_reference: $(CPU_REF_SRC) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $< -o $@ $(LDFLAGS_SSL)

$(BUILD_DIR)/hash_dataset: $(HASH_DATASET_SRC) $(KERNEL_SRC) $(SHA256_CUH) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $(HASH_DATASET_SRC) $(KERNEL_SRC) -o $@

$(BUILD_DIR)/validate: $(VALIDATE_SRC) $(KERNEL_SRC) $(SHA256_CUH) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $(VALIDATE_SRC) $(KERNEL_SRC) -o $@ $(LDFLAGS_SSL)

$(BUILD_DIR)/benchmark: $(BENCHMARK_SRC) $(SHA256_CUH) | $(BUILD_DIR)
	$(NVCC) $(NVCCFLAGS) $< -o $@ $(LDFLAGS_SSL)

N ?= 100000
run: all
	@mkdir -p $(DATA_DIR) results
	@echo "==> Step 1/4: cpu_reference ($(N) messages)"
	./$(BUILD_DIR)/cpu_reference $(N) $(DATA_DIR)/
	@echo "==> Step 2/4: hash_dataset"
	./$(BUILD_DIR)/hash_dataset $(DATA_DIR)/
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
		echo "  [MISS] $(FILE)  — $(TASK)  -> $(OWNER)"; \
	fi
