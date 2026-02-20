#!/bin/bash
#
# Run a benchmark with a specific overlay
#
# Usage: ./run-overlay.sh <overlay-name>
# Example: ./run-overlay.sh producers-4
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="${NAMESPACE:-korvet-benchmark}"

OVERLAY="$1"

if [ -z "$OVERLAY" ]; then
    echo "Usage: $0 <overlay-name>"
    echo "Example: $0 producers-4"
    exit 1
fi

OVERLAY_DIR="$BENCHMARK_DIR/overlays/$OVERLAY"

if [ ! -d "$OVERLAY_DIR" ]; then
    echo "Error: Overlay '$OVERLAY' not found at $OVERLAY_DIR"
    exit 1
fi

echo "=== Running Benchmark: $OVERLAY ==="
echo ""

# Delete any existing benchmark job
echo "Cleaning up previous benchmark job..."
kubectl delete job benchmark-producer -n "$NAMESPACE" --ignore-not-found
sleep 2

# Apply the overlay
echo "Applying overlay: $OVERLAY"
kubectl apply -k "$OVERLAY_DIR"

# Wait for Korvet to be ready
echo "Waiting for Korvet to be ready..."
kubectl wait --for=condition=ready pod -l app=korvet -n "$NAMESPACE" --timeout=120s

# Wait for benchmark job to complete
echo "Waiting for benchmark job to complete..."
kubectl wait --for=condition=complete job/benchmark-producer -n "$NAMESPACE" --timeout=600s

# Collect results
echo ""
echo "=== Benchmark Results ==="
kubectl logs -l app=benchmark,component=producer -n "$NAMESPACE" --tail=50

echo ""
echo "=== Benchmark Complete: $OVERLAY ==="

