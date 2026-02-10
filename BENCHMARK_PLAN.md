# Korvet Benchmark Testing Plan

## Goal
Gauge max throughput while measuring latency, CPU usage, and memory usage of all components (Korvet and Redis Enterprise) across 3 scenarios.

## Key Learnings from Previous Attempts

### Issue 1: Native Transports Disabled
The current `korvet-app/build.gradle` disables native I/O transports:
```
-Dio.lettuce.core.epoll=false
-Dio.lettuce.core.kqueue=false
-Dio.lettuce.core.iouring=false
-Dio.netty.noUnsafe=true
```
This forces NIO transport instead of native kqueue (macOS) or epoll (Linux), potentially causing significant performance degradation.

**Action**: Investigate if these can be re-enabled, or document performance with NIO transport.

### Issue 2: Partition Count
- Default partition count is 1 (`application.yml: default-partitions: 1`)
- For benchmarks, use 32 partitions (2× Redis shards) via `KORVET_SERVER_DEFAULT_PARTITIONS=32`
- Verify partition count after topic creation: `redis-cli -p 12000 HGET "korvet:topic:<name>" partitions`

### Issue 3: Original Benchmarks Environment
- Original 2.6M records/sec benchmarks were run in Kubernetes (Docker Desktop)
- Recent benchmarks (~180K records/sec) were run on host via `./gradlew :korvet-app:bootRun`
- Need to determine which environment to use for official benchmarks

---

## Environment Setup Checklist

### 1. Redis Enterprise
- [ ] Running in Docker on port 12000 with 16 shards
- [ ] Verify: `redis-cli -p 12000 PING`
- [ ] Flush before each test: `redis-cli -p 12000 FLUSHALL`

### 2. Korvet
- [ ] Decide: Run in Kubernetes OR on host
- [ ] Set partition count: `export KORVET_SERVER_DEFAULT_PARTITIONS=32`
- [ ] Start Korvet and verify it's running
- [ ] Verify metrics endpoint: `curl http://localhost:8080/actuator/prometheus`

### 3. Kafka Tools
- [ ] Installed via Homebrew: `brew install kafka`
- [ ] Verify: `kafka-producer-perf-test --version`

---

## Metrics to Collect

### Korvet Metrics (from /actuator/prometheus)
- `process_cpu_usage` - Korvet CPU usage
- `system_cpu_usage` - System CPU usage
- `jvm_memory_used_bytes{area="heap"}` - Heap memory
- `jvm_memory_used_bytes{area="nonheap"}` - Non-heap memory

### Redis Enterprise Metrics (from INFO stats)
- `instantaneous_ops_per_sec` - Operations per second
- `instantaneous_input_kbps` - Input bandwidth
- `instantaneous_output_kbps` - Output bandwidth
- `total_commands_processed` - Total commands

### Benchmark Tool Output
- Records/sec (throughput)
- MB/sec (bandwidth)
- Avg latency (ms)
- p50, p95, p99, p99.9 latency (ms)

---

## Scenario 1: 32 Producers Benchmark

### Setup
```bash
redis-cli -p 12000 FLUSHALL
TOPIC="benchmark-producers-$(date +%s)"
```

### Capture Baseline Metrics
```bash
redis-cli -p 12000 INFO stats > /tmp/redis_before.txt
curl -s http://localhost:8080/actuator/prometheus > /tmp/korvet_before.txt
```

### Run Benchmark
```bash
for i in $(seq 1 32); do
  kafka-producer-perf-test \
    --topic $TOPIC \
    --num-records 100000 \
    --record-size 1024 \
    --throughput -1 \
    --producer-props bootstrap.servers=localhost:9092 \
    2>&1 | tee /tmp/producer_$i.log &
done
wait
```

### Capture Post-Benchmark Metrics
```bash
redis-cli -p 12000 INFO stats > /tmp/redis_after.txt
curl -s http://localhost:8080/actuator/prometheus > /tmp/korvet_after.txt
```

### Verify Partition Count
```bash
redis-cli -p 12000 HGET "korvet:topic:$TOPIC" partitions
# Should be 32
```

---

## Scenario 2: 32 Consumers Benchmark

### Setup
```bash
# First produce data for consumers
TOPIC="benchmark-consumers-$(date +%s)"
GROUP="test-group-$(date +%s)"

# Produce 4M messages (125K per consumer × 32)
kafka-producer-perf-test \
  --topic $TOPIC \
  --num-records 4000000 \
  --record-size 1024 \
  --throughput -1 \
  --producer-props bootstrap.servers=localhost:9092
```

### Capture Baseline Metrics
```bash
redis-cli -p 12000 INFO stats > /tmp/redis_before.txt
curl -s http://localhost:8080/actuator/prometheus > /tmp/korvet_before.txt
```

### Run Benchmark
```bash
for i in $(seq 1 32); do
  kafka-consumer-perf-test \
    --bootstrap-server localhost:9092 \
    --topic $TOPIC \
    --group $GROUP \
    --messages 125000 \
    --timeout 120000 \
    2>&1 | tee /tmp/consumer_$i.log &
done
wait
```

### Capture Post-Benchmark Metrics
(same as Scenario 1)

---

## Scenario 3: 32 Producers + 32 Consumers

### Setup
```bash
redis-cli -p 12000 FLUSHALL
TOPIC="benchmark-combined-$(date +%s)"
GROUP="test-group-$(date +%s)"
```

### Run Benchmark (producers and consumers concurrently)
```bash
# Start 32 producers
for i in $(seq 1 32); do
  kafka-producer-perf-test \
    --topic $TOPIC \
    --num-records 100000 \
    --record-size 1024 \
    --throughput -1 \
    --producer-props bootstrap.servers=localhost:9092 \
    2>&1 | tee /tmp/producer_$i.log &
done

# Start 32 consumers
for i in $(seq 1 32); do
  kafka-consumer-perf-test \
    --bootstrap-server localhost:9092 \
    --topic $TOPIC \
    --group $GROUP \
    --messages 100000 \
    --timeout 180000 \
    2>&1 | tee /tmp/consumer_$i.log &
done

wait
```

---

## Open Questions

1. **Native transports**: Should we re-enable them for benchmarks? What was the Netty 4.2.x compatibility issue?
2. **Environment**: Should official benchmarks be run in Kubernetes or on host?
3. **Rebalance delay**: Current default is 10s. Should this be tuned for benchmarks?
4. **Consumer timeout**: Some consumers timed out at 120s. Need longer timeout or investigate root cause.

