.PHONY: help setup teardown benchmark test-producers results clean-jobs

NAMESPACE ?= korvet-benchmark
SCRIPTS_DIR := $(dir $(lastword $(MAKEFILE_LIST)))scripts

help:
	@echo "Korvet Kubernetes Benchmark"
	@echo ""
	@echo "Setup:"
	@echo "  make setup                    - Create namespace and base resources"
	@echo "  make teardown                 - Remove all benchmark resources"
	@echo ""
	@echo "Benchmarks:"
	@echo "  make benchmark                - Run full benchmark suite"
	@echo "  make test-producers           - Test number of producers (1, 2, 4, 8)"
	@echo ""
	@echo "Results:"
	@echo "  make results                  - Show benchmark results"
	@echo "  make clean-jobs               - Delete completed benchmark jobs"

setup:
	@echo "Creating namespace and base resources..."
	kubectl apply -k base/

teardown:
	@echo "Removing all benchmark resources..."
	kubectl delete namespace $(NAMESPACE) --ignore-not-found

test-producers:
	@echo "Running producers dimension benchmark..."
	./scripts/benchmark.sh --dimension producers

benchmark:
	@echo "Running full benchmark suite..."
	./scripts/benchmark.sh

results:
	@echo "Collecting benchmark results..."
	./scripts/collect-results.sh

clean-jobs:
	@echo "Deleting completed benchmark jobs..."
	kubectl delete jobs -l app=benchmark -n $(NAMESPACE)

# Individual overlay runs
run-%:
	./scripts/run-overlay.sh $*

