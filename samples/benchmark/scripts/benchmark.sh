#!/bin/bash
#
# Run full benchmark suite across all dimensions
#
# Usage: ./benchmark.sh [--dimension <name>]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="${NAMESPACE:-korvet-benchmark}"

# Parse arguments
DIMENSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --dimension|-d)
            DIMENSION="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--dimension <name>]"
            echo ""
            echo "Options:"
            echo "  --dimension, -d    Run only overlays matching this dimension prefix"
            echo "                     Example: --dimension producers"
            echo ""
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Find all overlays
OVERLAYS_DIR="$BENCHMARK_DIR/overlays"
if [ -n "$DIMENSION" ]; then
    OVERLAYS=$(ls -d "$OVERLAYS_DIR"/${DIMENSION}-* 2>/dev/null | xargs -n1 basename)
else
    OVERLAYS=$(ls -d "$OVERLAYS_DIR"/*/ 2>/dev/null | xargs -n1 basename)
fi

if [ -z "$OVERLAYS" ]; then
    echo "No overlays found"
    exit 1
fi

echo "=== Korvet Benchmark Suite ==="
echo "Namespace: $NAMESPACE"
echo "Overlays to run:"
for overlay in $OVERLAYS; do
    echo "  - $overlay"
done
echo ""

# Run each overlay
for overlay in $OVERLAYS; do
    echo ""
    echo "========================================"
    "$SCRIPT_DIR/run-overlay.sh" "$overlay"
    echo "========================================"
    echo ""
    
    # Brief pause between tests
    sleep 5
done

echo ""
echo "=== All Benchmarks Complete ==="
echo ""
echo "View results with: kubectl exec -it kafka-tools -n $NAMESPACE -- ls /results/"

