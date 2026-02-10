#!/bin/bash
# Comprehensive Korvet Benchmark Script
# Tests all combinations of producers, batch sizes, and pool sizes

set -e

# Configuration
REDIS_HOST=${REDIS_HOST:-localhost}
REDIS_PORT=${REDIS_PORT:-12000}
KORVET_HOST=${KORVET_HOST:-localhost}
KORVET_PORT=${KORVET_PORT:-9092}
KORVET_ACTUATOR_PORT=${KORVET_ACTUATOR_PORT:-8080}
RE_API_URL=${RE_API_URL:-https://localhost:9443}
RE_API_USER=${RE_API_USER:-admin@redis.com}
RE_API_PASS=${RE_API_PASS:-admin}

# Test parameters
TOPIC="benchmark-test"
PARTITIONS=16
RECORD_SIZE=1024
NUM_RECORDS=1000000
ACKS=1
LINGER_MS=0
COMPRESSION=none

# Parameter arrays - single optimal configuration
PRODUCERS=(8)
BATCH_SIZES=(1000)  # Number of messages per batch
POOL_SIZES=(8)

# Report file
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
REPORT_DIR="/tmp/korvet-benchmark-${TIMESTAMP}"
mkdir -p "${REPORT_DIR}"
REPORT_FILE="${REPORT_DIR}/comprehensive-report.txt"

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${REPORT_FILE}"
}

verify_prerequisites() {
    log "=== Verifying Prerequisites ==="

    for cmd in redis-cli kafka-producer-perf-test kafka-topics curl jq bc; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR: $cmd not found"
            exit 1
        fi
    done

    if ! redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING > /dev/null 2>&1; then
        log "ERROR: Redis Enterprise not running"
        exit 1
    fi

    log "All prerequisites met ✅"
    log "Note: Korvet will be started/restarted as needed during benchmarking"
}

flush_redis() {
    log "Flushing Redis database..."
    redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" FLUSHALL > /dev/null
    log "Database flushed ✅"
}

create_topic() {
    log "Creating topic ${TOPIC} with ${PARTITIONS} partitions..."
    kafka-topics --bootstrap-server "${KORVET_HOST}:${KORVET_PORT}" \
        --create --topic "${TOPIC}" --partitions "${PARTITIONS}" --replication-factor 1 > /dev/null 2>&1 || true
    log "Topic created ✅"
}

# Calculate batch size in bytes from number of messages
calculate_batch_size_bytes() {
    local num_messages=$1
    # Each message is RECORD_SIZE bytes, add some overhead for headers
    echo $((num_messages * (RECORD_SIZE + 100)))
}

collect_korvet_metrics() {
    local result_file=$1
    
    echo "" >> "${result_file}"
    echo "=== Korvet Metrics ===" >> "${result_file}"
    
    # Messages produced
    local messages=$(curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/prometheus" | \
        grep '^korvet_produce_messages_total' | grep -v '#' | \
        awk '{sum += $2} END {print sum}')
    echo "Messages produced: ${messages}" >> "${result_file}"
    
    # Bytes produced
    local bytes=$(curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/prometheus" | \
        grep '^korvet_produce_bytes_total' | grep -v '#' | \
        awk '{sum += $2} END {print sum}')
    local mb=$(echo "scale=2; ${bytes}/1024/1024" | bc)
    echo "Bytes produced: ${bytes} (${mb} MB)" >> "${result_file}"
    
    # CPU usage
    local process_cpu=$(curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/metrics/process.cpu.usage" | \
        jq -r '.measurements[0].value')
    local process_cpu_pct=$(echo "${process_cpu} * 100" | bc)
    echo "Korvet Process CPU: ${process_cpu_pct}%" >> "${result_file}"
    
    local system_cpu=$(curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/metrics/system.cpu.usage" | \
        jq -r '.measurements[0].value')
    local system_cpu_pct=$(echo "${system_cpu} * 100" | bc)
    echo "System CPU: ${system_cpu_pct}%" >> "${result_file}"
    
    # Memory usage
    local jvm_memory=$(curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/metrics/jvm.memory.used" | \
        jq -r '.measurements[0].value')
    local jvm_memory_mb=$(echo "scale=2; ${jvm_memory}/1024/1024" | bc)
    echo "JVM Memory Used: ${jvm_memory_mb} MB" >> "${result_file}"
}

collect_redis_metrics() {
    local result_file=$1

    echo "" >> "${result_file}"
    echo "=== Redis Enterprise Metrics ===" >> "${result_file}"

    # Shard distribution
    curl -sk -u "${RE_API_USER}:${RE_API_PASS}" "${RE_API_URL}/v1/shards/stats" | \
        jq -r '[.[] | {uid: .uid, used_memory_mb: (.intervals[0].used_memory / 1048576 | floor), no_of_keys: .intervals[0].no_of_keys}] |
        sort_by(.uid) | .[] | "Shard \(.uid): \(.used_memory_mb) MB, \(.no_of_keys) keys"' >> "${result_file}"

    echo "" >> "${result_file}"

    # CPU metrics per shard
    echo "Redis Enterprise CPU Usage:" >> "${result_file}"
    curl -sk -u "${RE_API_USER}:${RE_API_PASS}" "${RE_API_URL}/v1/shards/stats" | \
        jq -r '[.[] | {uid: .uid, cpu: ((.intervals[0].shard_cpu_system + .intervals[0].shard_cpu_user) * 100)}] |
        sort_by(.uid) | .[] | "  Shard \(.uid): \(.cpu)%"' >> "${result_file}"

    # Aggregate CPU
    local total_cpu=$(curl -sk -u "${RE_API_USER}:${RE_API_PASS}" "${RE_API_URL}/v1/shards/stats" | \
        jq '[.[] | (.intervals[0].shard_cpu_system + .intervals[0].shard_cpu_user)] | add * 100')
    echo "  Total CPU across all shards: ${total_cpu}%" >> "${result_file}"
}

run_benchmark_no_restart() {
    local num_producers=$1
    local batch_size_messages=$2
    local pool_size=$3

    local batch_size_bytes=$(calculate_batch_size_bytes "${batch_size_messages}")
    local test_name="producers-${num_producers}_batch-${batch_size_messages}msg_pool-${pool_size}"
    local result_file="${REPORT_DIR}/${test_name}.txt"

    log ""
    log "=========================================="
    log "Running: ${test_name}"
    log "  Producers: ${num_producers}"
    log "  Batch size: ${batch_size_messages} messages (${batch_size_bytes} bytes)"
    log "  Pool size: ${pool_size}"
    log "=========================================="

    # Write test configuration to result file
    {
        echo "Test: ${test_name}"
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "Configuration:"
        echo "  Topic: ${TOPIC}"
        echo "  Partitions: ${PARTITIONS}"
        echo "  Producers: ${num_producers}"
        echo "  Messages per producer: ${NUM_RECORDS}"
        echo "  Total messages: $((NUM_RECORDS * num_producers))"
        echo "  Record size: ${RECORD_SIZE} bytes"
        echo "  Batch size: ${batch_size_messages} messages (${batch_size_bytes} bytes)"
        echo "  Pool size: ${pool_size}"
        echo "  Acks: ${ACKS}"
        echo "  Compression: ${COMPRESSION}"
        echo ""
    } > "${result_file}"

    # Flush Redis and recreate topic
    flush_redis
    sleep 2
    create_topic
    sleep 2

    # Run benchmark
    log "Running benchmark..."
    if [ "${num_producers}" -eq 1 ]; then
        # Single producer
        kafka-producer-perf-test \
            --topic "${TOPIC}" \
            --num-records "${NUM_RECORDS}" \
            --record-size "${RECORD_SIZE}" \
            --throughput -1 \
            --producer-props \
            bootstrap.servers="${KORVET_HOST}:${KORVET_PORT}" \
            acks="${ACKS}" \
            batch.size="${batch_size_bytes}" \
            linger.ms="${LINGER_MS}" \
            compression.type="${COMPRESSION}" \
            partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner \
            2>&1 | tee -a "${result_file}"
    else
        # Multiple producers in parallel
        tmpdir=$(mktemp -d)
        pids=""
        start_time=$(date +%s)

        for i in $(seq 1 "${num_producers}"); do
            logfile="${tmpdir}/producer-${i}.log"
            (kafka-producer-perf-test \
                --topic "${TOPIC}" \
                --num-records "${NUM_RECORDS}" \
                --record-size "${RECORD_SIZE}" \
                --throughput -1 \
                --producer-props \
                bootstrap.servers="${KORVET_HOST}:${KORVET_PORT}" \
                acks="${ACKS}" \
                batch.size="${batch_size_bytes}" \
                linger.ms="${LINGER_MS}" \
                compression.type="${COMPRESSION}" \
                partitioner.class=org.apache.kafka.clients.producer.RoundRobinPartitioner \
                > "${logfile}" 2>&1) &
            pids="${pids} $!"
        done

        # Wait for all producers
        for pid in ${pids}; do
            wait "${pid}"
        done

        end_time=$(date +%s)
        duration=$((end_time - start_time))

        # Collect results
        {
            echo ""
            echo "=== Individual Producer Results ==="
            echo ""
            for i in $(seq 1 "${num_producers}"); do
                echo "Producer ${i}:"
                tail -1 "${tmpdir}/producer-${i}.log"
                echo ""
            done

            echo "=== Aggregate Results ==="
            echo ""
            total_messages=$((NUM_RECORDS * num_producers))
            echo "Total messages: ${total_messages}"
            echo "Total duration: ${duration} seconds"
            if [ "${duration}" -gt 0 ]; then
                aggregate_throughput=$((total_messages / duration))
                echo "Aggregate throughput: ${aggregate_throughput} rec/sec"
                throughput_mb=$(echo "scale=2; ${aggregate_throughput} * ${RECORD_SIZE} / 1024 / 1024" | bc)
                echo "Aggregate throughput: ${throughput_mb} MB/sec"
            fi
        } >> "${result_file}"

        rm -rf "${tmpdir}"
    fi

    # Collect metrics
    sleep 2
    collect_korvet_metrics "${result_file}"
    collect_redis_metrics "${result_file}"

    log "Test complete: ${test_name}"
    log "Results saved to: ${result_file}"
}

restart_korvet() {
    local pool_size=$1

    # Find Korvet process
    local korvet_pid=$(pgrep -f "korvet-app.*jar" || true)

    if [ -n "${korvet_pid}" ]; then
        log "Stopping Korvet (PID: ${korvet_pid})..."
        kill "${korvet_pid}" || true
        sleep 3

        # Force kill if still running
        if ps -p "${korvet_pid}" > /dev/null 2>&1; then
            kill -9 "${korvet_pid}" || true
            sleep 2
        fi
    fi

    # Start Korvet with new pool size
    log "Starting Korvet with pool size ${pool_size}..."
    cd "$(dirname "$0")/.."
    ./gradlew :korvet-app:bootRun --args="--korvet.redis.pool-size=${pool_size} --korvet.redis.port=${REDIS_PORT}" > /dev/null 2>&1 &

    # Wait for Korvet to be ready
    log "Waiting for Korvet to be ready..."
    for i in {1..60}; do
        if curl -s "http://${KORVET_HOST}:${KORVET_ACTUATOR_PORT}/actuator/health" > /dev/null 2>&1; then
            log "Korvet is ready ✅"
            return 0
        fi
        sleep 1
    done

    log "ERROR: Korvet failed to start"
    exit 1
}

generate_summary_report() {
    log ""
    log "=== Generating Summary Report ==="

    local summary_file="${REPORT_DIR}/SUMMARY.txt"

    {
        echo "=========================================="
        echo "Korvet Comprehensive Benchmark Summary"
        echo "=========================================="
        echo ""
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Report Directory: ${REPORT_DIR}"
        echo ""
        echo "Test Configuration:"
        echo "  Topic: ${TOPIC}"
        echo "  Partitions: ${PARTITIONS}"
        echo "  Record Size: ${RECORD_SIZE} bytes"
        echo "  Messages per test: ${NUM_RECORDS} per producer"
        echo ""
        echo "Parameter Matrix:"
        echo "  Producers: ${PRODUCERS[*]}"
        echo "  Batch Sizes (messages): ${BATCH_SIZES[*]}"
        echo "  Pool Sizes: ${POOL_SIZES[*]}"
        echo "  Total tests: $((${#PRODUCERS[@]} * ${#BATCH_SIZES[@]} * ${#POOL_SIZES[@]}))"
        echo ""
        echo "=========================================="
        echo "Results Summary"
        echo "=========================================="
        echo ""
        printf "%-10s %-12s %-10s %-15s %-12s %-18s %-18s %-12s\n" \
            "Producers" "Batch(msg)" "Pool" "Total Msgs" "Duration(s)" "Throughput(rec/s)" "Throughput(MB/s)" "Korvet CPU%"
        echo "----------------------------------------------------------------------------------------------------------------------------"

        for result_file in "${REPORT_DIR}"/producers-*.txt; do
            if [ -f "${result_file}" ]; then
                # Extract test parameters from filename
                local filename=$(basename "${result_file}" .txt)
                local producers=$(echo "${filename}" | sed 's/producers-\([0-9]*\)_.*/\1/')
                local batch=$(echo "${filename}" | sed 's/.*_batch-\([0-9]*\)msg_.*/\1/')
                local pool=$(echo "${filename}" | sed 's/.*_pool-\([0-9]*\)/\1/')

                # Extract metrics from result file
                local total_msgs=$(grep "Total messages:" "${result_file}" | awk '{print $3}' || echo "N/A")
                local duration=$(grep "Total duration:" "${result_file}" | awk '{print $3}' || echo "N/A")
                local throughput_rec=$(grep "Aggregate throughput:" "${result_file}" | head -1 | awk '{print $3}' || echo "N/A")
                local throughput_mb=$(grep "Aggregate throughput:" "${result_file}" | tail -1 | awk '{print $3}' || echo "N/A")
                local cpu=$(grep "Korvet Process CPU:" "${result_file}" | awk '{print $4}' || echo "N/A")

                printf "%-10s %-12s %-10s %-15s %-12s %-18s %-18s %-12s\n" \
                    "${producers}" "${batch}" "${pool}" "${total_msgs}" "${duration}" "${throughput_rec}" "${throughput_mb}" "${cpu}"
            fi
        done

        echo ""
        echo "=========================================="
        echo "Individual Test Results"
        echo "=========================================="
        echo ""
        echo "Detailed results for each test are available in:"
        for result_file in "${REPORT_DIR}"/producers-*.txt; do
            if [ -f "${result_file}" ]; then
                echo "  - $(basename "${result_file}")"
            fi
        done

    } > "${summary_file}"

    cat "${summary_file}"
    log ""
    log "Summary report saved to: ${summary_file}"
}

# Main execution
main() {
    log "=========================================="
    log "Korvet Comprehensive Benchmark"
    log "=========================================="
    log ""
    log "Report directory: ${REPORT_DIR}"
    log ""

    verify_prerequisites

    local total_tests=$((${#PRODUCERS[@]} * ${#BATCH_SIZES[@]} * ${#POOL_SIZES[@]}))
    local current_test=0

    log ""
    log "Running ${total_tests} benchmark combinations..."
    log ""

    # Group tests by pool size to minimize Korvet restarts
    for pool_size in "${POOL_SIZES[@]}"; do
        log ""
        log "=========================================="
        log "Testing with pool size: ${pool_size}"
        log "=========================================="

        # Restart Korvet once for this pool size
        restart_korvet "${pool_size}"
        sleep 5

        for num_producers in "${PRODUCERS[@]}"; do
            for batch_size in "${BATCH_SIZES[@]}"; do
                current_test=$((current_test + 1))
                log "Progress: ${current_test}/${total_tests}"
                run_benchmark_no_restart "${num_producers}" "${batch_size}" "${pool_size}"
                sleep 5  # Cool down between tests
            done
        done
    done

    generate_summary_report

    log ""
    log "=========================================="
    log "All benchmarks complete! ✅"
    log "=========================================="
    log ""
    log "Results saved to: ${REPORT_DIR}"
}

# Run main
main

