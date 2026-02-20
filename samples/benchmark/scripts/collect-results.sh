#!/bin/bash
#
# Collect and display benchmark results from the PVC
#
# Usage: ./collect-results.sh [--format csv|json|table]
#

set -e

NAMESPACE="${NAMESPACE:-korvet-benchmark}"
FORMAT="${1:-table}"

echo "=== Benchmark Results ==="
echo ""

# Get results from the kafka-tools pod (which has the PVC mounted)
# First, check if kafka-tools pod exists and has the volume
if ! kubectl get pod kafka-tools -n "$NAMESPACE" &>/dev/null; then
    echo "Error: kafka-tools pod not found. Run 'make setup' first."
    exit 1
fi

# List all result files
echo "Result files:"
kubectl exec kafka-tools -n "$NAMESPACE" -- ls -la /results/ 2>/dev/null || echo "No results yet"

echo ""
echo "Results content:"
kubectl exec kafka-tools -n "$NAMESPACE" -- sh -c 'for f in /results/*.json; do [ -f "$f" ] && cat "$f" && echo ""; done' 2>/dev/null || echo "No JSON results found"

