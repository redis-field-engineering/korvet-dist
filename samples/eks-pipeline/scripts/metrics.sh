#!/bin/bash

# Usage: ./metrics.sh [component...]
# Components: logstash, korvet, redis, s3
# If no component specified, shows all

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

run_with_timeout() {
    perl -e 'alarm shift; exec @ARGV' "$@"
}

cleanup_port_forward() {
    local pid="$1"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

show_logstash() {
    echo "=== Logstash Metrics ==="
    kubectl port-forward deployment/logstash 9600:9600 -n korvet >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    curl -s http://localhost:9600/_node/stats/pipelines 2>/dev/null | jq '{
        events_in: .pipelines.main.events.in,
        events_out: .pipelines.main.events.out,
        events_filtered: .pipelines.main.events.filtered,
        duration_seconds: (.pipelines.main.events.duration_in_millis / 1000),
        throughput_per_sec: (if .pipelines.main.events.duration_in_millis > 0 then (.pipelines.main.events.out / .pipelines.main.events.duration_in_millis * 1000 | floor) else 0 end)
    }' || echo "Logstash not available"
    kill $PF_PID 2>/dev/null
    wait $PF_PID 2>/dev/null
    echo ""
}

show_korvet() {
    echo "=== Korvet Metrics ==="
    kubectl port-forward deployment/korvet 8080:8080 -n korvet >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2

    # Get key metrics and format nicely
    METRICS=$(curl -s http://localhost:8080/actuator/prometheus 2>/dev/null)
    if [ -n "$METRICS" ]; then
        echo "Produce bytes per partition:"
        echo "$METRICS" | grep "^korvet_produce_bytes_total" | sed 's/korvet_produce_bytes_total{partition="/  partition /; s/",topic="logs"} / = /; s/$/ bytes/'
        echo ""
        echo "Produce messages per partition:"
        echo "$METRICS" | grep "^korvet_produce_messages_total" | sed 's/korvet_produce_messages_total{partition="/  partition /; s/",topic="logs"} / = /; s/$/ messages/'
        echo ""
        echo "Archival:"
        echo "$METRICS" | grep "^korvet_archival" | head -5
    else
        echo "Korvet not available"
    fi
    kill $PF_PID 2>/dev/null
    wait $PF_PID 2>/dev/null
    echo ""
}

show_redis() {
    echo "=== Redis Metrics ==="
    REDIS_PASSWORD=$(kubectl get secret redb-korvet-db -n redis -o jsonpath='{.data.password}' | base64 -d)
    REDIS_PORT=16379

    kubectl port-forward svc/korvet-db -n redis ${REDIS_PORT}:19750 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2

    if ! nc -z localhost ${REDIS_PORT} >/dev/null 2>&1; then
        echo "Redis not available"
        cleanup_port_forward "$PF_PID"
        echo ""
        return
    fi

    echo "Database size:"
    run_with_timeout 10 redis-cli -h localhost -p ${REDIS_PORT} -a "$REDIS_PASSWORD" --no-auth-warning DBSIZE 2>/dev/null | sed 's/^/  /' || echo "  Redis not available"

    echo ""
    echo "Memory usage:"
    run_with_timeout 10 redis-cli -h localhost -p ${REDIS_PORT} -a "$REDIS_PASSWORD" --no-auth-warning INFO memory 2>/dev/null | \
        grep -E "used_memory_human|maxmemory_human" | sed 's/^/  /' || echo "  Redis not available"

    echo ""
    echo "Stream counts (sample):"
    # Stream keys are now logical keys like korvet:stream:<topic>:<partition> with bucket suffixes :b<epoch>.
    # Use SCAN instead of KEYS to avoid blocking Redis on large datasets.
    KEYS=$(run_with_timeout 10 redis-cli -h localhost -p ${REDIS_PORT} -a "$REDIS_PASSWORD" --no-auth-warning \
        --scan --pattern 'korvet:stream:logs:*' 2>/dev/null | grep -E ':b[0-9]+$' | head -4)
    if [ -z "$KEYS" ]; then
        echo "  No matching bucket stream keys found"
    else
        for key in $KEYS; do
            LEN=$(run_with_timeout 10 redis-cli -h localhost -p ${REDIS_PORT} -a "$REDIS_PASSWORD" --no-auth-warning XLEN "$key" 2>/dev/null)
            echo "  $key: $LEN entries"
        done
    fi
    cleanup_port_forward "$PF_PID"
    echo ""
}

show_s3() {
    echo "=== S3 Metrics ==="

    # Try to get bucket from terraform, or use S3_BUCKET env var
    if [ -n "$S3_BUCKET" ]; then
        : # Use existing S3_BUCKET
    elif [ -f "$ROOT_DIR/terraform/terraform.tfstate" ]; then
        cd "$ROOT_DIR/terraform"
        S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
    else
        S3_BUCKET=$(aws s3 ls 2>/dev/null | grep korvet-poc | awk '{print $3}' | head -1)
    fi

    if [ -z "$S3_BUCKET" ]; then
        echo "  Error: Could not get S3 bucket name from Terraform output"
        return
    fi

    echo "Bucket: $S3_BUCKET"
    echo ""

    # Get summary
    SUMMARY=$(aws s3 ls "s3://$S3_BUCKET/" --recursive --summarize 2>/dev/null | tail -2)
    TOTAL_OBJECTS=$(echo "$SUMMARY" | grep "Total Objects" | awk '{print $3}')
    TOTAL_SIZE=$(echo "$SUMMARY" | grep "Total Size" | awk '{print $3}')

    # Convert bytes to human readable
    if [ -n "$TOTAL_SIZE" ]; then
        if [ "$TOTAL_SIZE" -gt 1073741824 ]; then
            SIZE_HR=$(echo "scale=2; $TOTAL_SIZE / 1073741824" | bc)
            SIZE_UNIT="GB"
        elif [ "$TOTAL_SIZE" -gt 1048576 ]; then
            SIZE_HR=$(echo "scale=2; $TOTAL_SIZE / 1048576" | bc)
            SIZE_UNIT="MB"
        else
            SIZE_HR=$(echo "scale=2; $TOTAL_SIZE / 1024" | bc)
            SIZE_UNIT="KB"
        fi
        echo "Total objects: $TOTAL_OBJECTS"
        echo "Total size: ${SIZE_HR} ${SIZE_UNIT}"
    fi

    echo ""
    echo "Objects per partition:"
    for i in 0 1 2 3; do
        COUNT=$(aws s3 ls "s3://$S3_BUCKET/korvet/delta/korvet/stream/logs/$i/" --recursive 2>/dev/null | wc -l | tr -d ' ')
        echo "  logs/$i: $COUNT files"
    done

    echo ""
    echo "Recent files (by time):"
    aws s3 ls "s3://$S3_BUCKET/korvet/delta/" --recursive 2>/dev/null | sort -k1,2 | tail -5 | awk '{print "  " $1 " " $2 " - " $3 " bytes"}'
    echo ""
}

# Parse arguments
COMPONENTS="$@"

# If no arguments, show all
if [ -z "$COMPONENTS" ]; then
    COMPONENTS="logstash korvet redis s3"
fi

# Show requested components
for component in $COMPONENTS; do
    case "$component" in
        logstash)
            show_logstash
            ;;
        korvet)
            show_korvet
            ;;
        redis)
            show_redis
            ;;
        s3)
            show_s3
            ;;
        *)
            echo "Unknown component: $component"
            echo "Available: logstash, korvet, redis, s3"
            exit 1
            ;;
    esac
done
