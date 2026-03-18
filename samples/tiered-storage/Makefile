.PHONY: help up down clean logs test-tiered test-produce test-consume test-verify status redis-cli

# Configurable parameters (matching kafka-producer-perf-test naming)
NUM_RECORDS ?= 500
RECORD_SIZE ?= 1024
THROUGHPUT ?= 100

help:
	@echo "Korvet Tiered Storage Sample"
	@echo ""
	@echo "Prerequisites:"
	@echo "  - Redis Enterprise Flex database running on localhost:12000"
	@echo ""
	@echo "Setup:"
	@echo "  make up       - Start Korvet with tiered storage + MinIO"
	@echo "  make down     - Stop services"
	@echo "  make clean    - Stop services, remove volumes, and flush Redis"
	@echo "  make logs     - View Korvet logs"
	@echo "  make status   - Check service status"
	@echo ""
	@echo "Tests:"
	@echo "  make test-tiered  - Run full tiered storage test"
	@echo "  make test-produce - Produce messages to topic"
	@echo "  make test-consume - Consume messages from topic"
	@echo "  make test-verify  - Verify data in both tiers"
	@echo ""
	@echo "Producer Parameters:"
	@echo "  NUM_RECORDS=500    - Number of messages to produce (default: 500)"
	@echo "  RECORD_SIZE=1024   - Size of each message in bytes (default: 1024)"
	@echo "  THROUGHPUT=100     - Messages per second, -1 for unlimited (default: 100)"
	@echo ""
	@echo "  Example: make test-produce NUM_RECORDS=10000 THROUGHPUT=500"
	@echo ""
	@echo "Debug:"
	@echo "  make redis-cli    - Connect to Redis CLI"
	@echo "  make minio        - Open MinIO console"
	@echo "  make logs-archiver - View archiver logs"

up:
	@echo "Starting Korvet with tiered storage..."
	@echo ""
	@echo "Configuration:"
	@echo "  Hot tier:        Redis @ localhost:12000"
	@echo "  Cold tier:       MinIO (S3-compatible) @ localhost:9000"
	@echo "  Bucket duration: 10 seconds"
	@echo ""
	docker compose up -d
	@echo "Waiting for services to be healthy..."
	@sleep 15
	@echo ""
	@echo "✓ Services started!"
	@echo "  Kafka endpoint: localhost:9092"
	@echo "  Actuator:       http://localhost:8080/actuator/health"
	@echo "  MinIO Console:  http://localhost:9001 (minioadmin/minioadmin)"
	@echo ""
	@echo "Run 'make test-tiered' to test tiered storage"

down:
	@echo "Stopping services..."
	docker compose down

clean:
	@echo "Cleaning up all data..."
	docker compose down -v
	@echo "Flushing Redis..."
	redis-cli -p 12000 FLUSHALL || true
	@echo "✓ Cleanup complete"

logs:
	docker compose logs -f korvet

logs-archiver:
	@echo "=== Archiver Logs ==="
	@docker compose logs korvet 2>&1 | grep -i -E "(archiv|tiered|delta)" | tail -30

status:
	@echo "Service Status:"
	@docker compose ps
	@echo ""
	@echo "Korvet Health:"
	@curl -s http://localhost:8080/actuator/health 2>/dev/null | jq . || echo "Korvet not ready"

# Create topic with tiered storage enabled
create-topic:
	@echo "Creating topic with tiered storage enabled..."
	@docker compose exec kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 \
		--create --topic tiered-test --partitions 1 \
		--config remote.storage.enable=true \
		--config local.retention.ms=15000 \
		--config retention.ms=86400000 \
		2>/dev/null || echo "Topic may already exist"
	@echo "Setting bucket duration to 10 seconds..."
	@docker compose exec kafka-tools /opt/kafka/bin/kafka-configs.sh \
		--bootstrap-server korvet:9092 \
		--entity-type topics --entity-name tiered-test \
		--alter --add-config bucket.duration.ms=10000 \
		2>/dev/null || true

describe-topic:
	@echo "=== Topic Configuration ==="
	@docker compose exec kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 --describe --topic tiered-test

# Main test
test-tiered:
	@echo "=== Tiered Storage Test ==="
	@echo ""
	@echo "Configuration:"
	@echo "  - Bucket duration: 10 seconds"
	@echo "  - Archiver interval: 5 seconds"
	@echo "  - Topic: tiered-test (with remote.storage.enable=true)"
	@echo ""
	@echo "Step 1: Creating topic..."
	@$(MAKE) create-topic
	@echo ""
	@echo "Step 2: Producing messages..."
	@$(MAKE) test-produce
	@echo ""
	@echo "Step 3: Consuming messages immediately (before archival)..."
	@$(MAKE) test-consume
	@echo ""
	@echo "Step 4: Waiting 30 seconds for bucket rotation and archival..."
	@for i in 1 2 3 4 5 6; do sleep 5; echo "  $$((i*5))s elapsed..."; done
	@echo ""
	@echo "Step 5: Verifying data archived to cold tier..."
	@$(MAKE) test-verify

# Produce messages
test-produce:
	@echo "Producing $(NUM_RECORDS) messages ($(RECORD_SIZE) bytes each) at $(THROUGHPUT) msg/sec..."
	@docker compose exec kafka-tools /opt/kafka/bin/kafka-producer-perf-test.sh \
		--topic tiered-test --num-records $(NUM_RECORDS) --record-size $(RECORD_SIZE) --throughput $(THROUGHPUT) \
		--producer-props bootstrap.servers=korvet:9092

# Consume messages without consumer group (direct partition read spans both tiers)
test-consume:
	@echo "Consuming messages (direct partition read, no consumer group)..."
	@COUNT=$$(docker compose exec -T kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 --topic tiered-test \
		--partition 0 --offset earliest \
		--max-messages $(NUM_RECORDS) --timeout-ms 30000 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$COUNT" -ge "$(NUM_RECORDS)" ]; then \
		echo "✓ Consumed $$COUNT messages"; \
	else \
		echo "⚠ Consumed only $$COUNT messages (expected $(NUM_RECORDS))"; \
	fi

# Verify data in both tiers
test-verify:
	@echo "=== Verifying Data in Both Tiers ==="
	@echo ""
	@echo "Hot tier (Redis streams):"
	@redis-cli -p 12000 KEYS 'korvet:stream:tiered-test:*' 2>/dev/null | head -10 || echo "  Could not connect"
	@echo ""
	@echo "Cold tier (MinIO/S3):"
	@docker compose exec minio mc alias set myminio http://localhost:9000 minioadmin minioadmin >/dev/null 2>&1 || true
	@docker compose exec minio mc ls myminio/korvet/ --recursive 2>/dev/null | head -20 || echo "  No files in cold storage"
	@echo ""
	@echo "Archiver logs:"
	@docker compose logs korvet 2>&1 | grep -i -E "(archived|error)" | tail -5 || echo "  No archiver logs"

redis-cli:
	@echo "Connecting to Redis at localhost:12000..."
	redis-cli -p 12000

minio:
	@echo "Opening MinIO console..."
	@open http://localhost:9001 || xdg-open http://localhost:9001 || echo "Open http://localhost:9001 in your browser"

.DEFAULT_GOAL := help
