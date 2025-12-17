.PHONY: help up down clean logs test-producer test-consumer test-baseline test-high-throughput test-large-messages test-consumer-group test-sustained dashboard metrics status

help:
	@echo "Korvet Load Testing Makefile"
	@echo ""
	@echo "Setup:"
	@echo "  make up                    - Start all services"
	@echo "  make down                  - Stop all services"
	@echo "  make clean                 - Stop services and remove volumes"
	@echo "  make logs                  - View logs from all services"
	@echo "  make status                - Check service status"
	@echo ""
	@echo "Basic Tests:"
	@echo "  make test-producer         - Run producer performance test"
	@echo "  make test-consumer         - Run consumer performance test"
	@echo "  make test-basic            - Run basic end-to-end test"
	@echo ""
	@echo "Test Scenarios:"
	@echo "  make test-baseline         - Baseline performance (100K msgs, 1KB, 10K/sec)"
	@echo "  make test-high-throughput  - High throughput test (1M msgs, unlimited)"
	@echo "  make test-large-messages   - Large message test (10K msgs, 100KB)"
	@echo "  make test-consumer-group   - Consumer group test (4 consumers)"
	@echo "  make test-sustained        - Sustained load test (10 minutes)"
	@echo ""
	@echo "Monitoring:"
	@echo "  make dashboard             - Open Grafana dashboard"
	@echo "  make metrics               - Open Prometheus metrics"
	@echo "  make redis-cli             - Connect to Redis CLI"
	@echo ""
	@echo "Advanced:"
	@echo "  make test-all              - Run all test scenarios"
	@echo "  make benchmark             - Run comprehensive benchmark suite"

up:
	@echo "Starting Korvet load testing environment..."
	docker compose up -d
	@echo "Waiting for services to be healthy..."
	@sleep 10
	@echo ""
	@echo "✓ Services started successfully!"
	@echo ""
	@echo "Korvet:     http://localhost:9092"
	@echo "Prometheus: http://localhost:9090"
	@echo "Grafana:    http://localhost:3000 (admin/admin)"
	@echo ""
	@echo "Run 'make test-basic' to start testing"

down:
	@echo "Stopping services..."
	docker compose down

clean:
	@echo "Cleaning up all data..."
	docker compose down -v
	@echo "✓ Cleanup complete"

logs:
	docker compose logs -f

status:
	@echo "Service Status:"
	@docker compose ps
	@echo ""
	@echo "Korvet Health:"
	@curl -s http://localhost:8080/actuator/health | jq . || echo "Korvet not ready"

# Basic Tests
test-producer:
	@echo "Running producer performance test..."
	@echo "Configuration: 100K messages, 1KB size, 10K msg/sec target"
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic perf-test \
		--num-records 100000 \
		--record-size 1024 \
		--throughput 10000 \
		--producer-props bootstrap.servers=korvet:9092

test-consumer:
	@echo "Running consumer performance test..."
	@echo "Configuration: Consume all messages from perf-test topic"
	@echo ""
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic perf-test \
		--messages 100000 \
		--bootstrap-server korvet:9092 \
		--group perf-test-consumer \
		--show-detailed-stats

test-basic:
	@echo "Running basic end-to-end test..."
	@echo ""
	@echo "Step 1: Producing 10,000 messages..."
	@docker compose exec kafka-tools kafka-producer-perf-test \
		--topic basic-test \
		--num-records 10000 \
		--record-size 1024 \
		--throughput 1000 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Step 2: Consuming messages..."
	@docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic basic-test \
		--messages 10000 \
		--bootstrap-server korvet:9092 \
		--group basic-test-consumer \
		--show-detailed-stats
	@echo ""
	@echo "✓ Basic test complete!"

# Test Scenarios
test-load:
	@echo "=== Load Test ==="
	@echo "Configuration:"
	@echo "  - Messages: 10,000,000"
	@echo "  - Message size: 1KB"
	@echo "  - Target throughput: unlimited"
	@echo "  - Duration: ~2-5 minutes depending on hardware"
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic load-test \
		--num-records 10000000 \
		--record-size 1024 \
		--throughput -1 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Consuming messages..."
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic load-test \
		--messages 10000000 \
		--bootstrap-server korvet:9092 \
		--group load-consumer

test-baseline:
	@echo "=== Baseline Performance Test ==="
	@echo "Configuration:"
	@echo "  - Messages: 1,000,000"
	@echo "  - Message size: 1KB"
	@echo "  - Target throughput: 10,000 msg/sec"
	@echo "  - Partitions: 1"
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic baseline-test \
		--num-records 1000000 \
		--record-size 1024 \
		--throughput 10000 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Consuming messages..."
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic baseline-test \
		--messages 1000000 \
		--bootstrap-server korvet:9092 \
		--group baseline-consumer

test-high-throughput:
	@echo "=== High Throughput Stress Test ==="
	@echo "Configuration:"
	@echo "  - Messages: 50,000,000"
	@echo "  - Message size: 1KB"
	@echo "  - Target throughput: unlimited"
	@echo "  - Duration: ~10-20 minutes depending on hardware"
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic high-throughput-test \
		--num-records 50000000 \
		--record-size 1024 \
		--throughput -1 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Consuming messages..."
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic high-throughput-test \
		--messages 50000000 \
		--bootstrap-server korvet:9092 \
		--group high-throughput-consumer

test-large-messages:
	@echo "=== Large Message Load Test ==="
	@echo "Configuration:"
	@echo "  - Messages: 100,000"
	@echo "  - Message size: 100KB"
	@echo "  - Target throughput: unlimited"
	@echo "  - Total data: ~10GB"
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic large-message-test \
		--num-records 100000 \
		--record-size 102400 \
		--throughput -1 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Consuming messages..."
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic large-message-test \
		--messages 100000 \
		--bootstrap-server korvet:9092 \
		--group large-message-consumer

test-consumer-group:
	@echo "=== Consumer Group Performance Test ==="
	@echo "Configuration:"
	@echo "  - Consumers: 4"
	@echo "  - Partitions: 4"
	@echo "  - Messages: 100,000"
	@echo ""
	@echo "Producing messages to 4 partitions..."
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic consumer-group-test \
		--num-records 100000 \
		--record-size 1024 \
		--throughput 10000 \
		--producer-props bootstrap.servers=korvet:9092
	@echo ""
	@echo "Starting 4 consumers in parallel..."
	@echo "Note: This will show output from the first consumer only"
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic consumer-group-test \
		--messages 100000 \
		--bootstrap-server korvet:9092 \
		--group consumer-group-test \
		--threads 4

test-sustained:
	@echo "=== Sustained Load Test ==="
	@echo "Configuration:"
	@echo "  - Duration: 30 minutes"
	@echo "  - Target throughput: 10,000 msg/sec"
	@echo "  - Message size: 1KB"
	@echo "  - Total messages: 18,000,000"
	@echo ""
	@echo "This will run for 30 minutes. Press Ctrl+C to stop early."
	@echo ""
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic sustained-test \
		--num-records 18000000 \
		--record-size 1024 \
		--throughput 10000 \
		--producer-props bootstrap.servers=korvet:9092

test-all:
	@echo "Running all test scenarios..."
	@echo ""
	@make test-baseline
	@echo ""
	@echo "Waiting 5 seconds before next test..."
	@sleep 5
	@make test-high-throughput
	@echo ""
	@echo "Waiting 5 seconds before next test..."
	@sleep 5
	@make test-large-messages
	@echo ""
	@echo "Waiting 5 seconds before next test..."
	@sleep 5
	@make test-consumer-group
	@echo ""
	@echo "✓ All tests complete!"

benchmark:
	@echo "Running comprehensive benchmark suite..."
	@echo "This will take approximately 15-20 minutes"
	@echo ""
	@./scripts/benchmark.sh

# Monitoring
dashboard:
	@echo "Opening Grafana dashboard..."
	@echo "URL: http://localhost:3000"
	@echo "Login: admin/admin"
	@open http://localhost:3000 || xdg-open http://localhost:3000 || echo "Please open http://localhost:3000 in your browser"

metrics:
	@echo "Opening Prometheus metrics..."
	@echo "URL: http://localhost:9090"
	@open http://localhost:9090 || xdg-open http://localhost:9090 || echo "Please open http://localhost:9090 in your browser"

redis-cli:
	@echo "Connecting to Redis CLI..."
	@echo "Useful commands:"
	@echo "  KEYS korvet:*              - List all Korvet keys"
	@echo "  XLEN korvet:topic:0        - Get message count"
	@echo "  XRANGE korvet:topic:0 - +  - Read messages"
	@echo ""
	docker compose exec redis redis-cli

# Utility targets
.DEFAULT_GOAL := help
