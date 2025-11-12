.PHONY: help up down restart logs producer consumer redis-cli topics clean

# Default target
help:
	@echo "Korvet Kafka CLI Demo - Available Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make up         - Start all services"
	@echo "  make down       - Stop all services"
	@echo ""
	@echo "Interactive Demo:"
	@echo "  make producer   - Start interactive producer"
	@echo "  make consumer   - Start interactive consumer"
	@echo ""
	@echo "Utilities:"
	@echo "  make topics     - List all topics"
	@echo "  make redis-cli  - Connect to Redis CLI"
	@echo "  make logs       - View all logs"
	@echo "  make clean      - Stop and remove all data"
	@echo ""

# Start all services
up:
	docker compose up -d
	@echo ""
	@echo "Services started! Wait 10-15 seconds for everything to initialize."
	@echo "Then run 'make producer' and 'make consumer' in separate terminals."

# Stop all services
down:
	docker compose down

# Restart all services
restart:
	docker compose restart

# View logs
logs:
	docker compose logs -f

# Start interactive producer
producer:
	@echo "Starting kafka-console-producer..."
	@echo "Type messages (one per line) and press Enter."
	@echo "Press Ctrl+C to exit."
	@echo ""
	docker compose exec kafka-tools /opt/kafka/bin/kafka-console-producer.sh \
		--bootstrap-server korvet:9092 \
		--topic demo-topic \
		--producer-property enable.idempotence=false

# Start interactive consumer
consumer:
	@echo "Starting kafka-console-consumer..."
	@echo "Reading from beginning of topic..."
	@echo "Press Ctrl+C to exit."
	@echo ""
	docker compose exec kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 \
		--topic demo-topic \
		--from-beginning

# Connect to Redis CLI
redis-cli:
	@echo "Connecting to Redis..."
	@echo "Try these commands:"
	@echo "  KEYS \"default:*\""
	@echo "  XLEN \"default:demo-topic:0\""
	@echo "  XRANGE \"default:demo-topic:0\" - + COUNT 10"
	@echo ""
	docker compose exec redis redis-cli

# List topics
topics:
	@echo "Listing topics..."
	docker compose exec kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 \
		--list

# Clean up everything
clean:
	docker compose down -v
	@echo "All services stopped and data removed."

