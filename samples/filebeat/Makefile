# Korvet Filebeat Sample - Makefile
# Convenient shortcuts for common tasks

.PHONY: help up down restart logs clean redis-cli

# Default target
help:
	@echo "Korvet Filebeat Sample - Available Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make up              - Start all services"
	@echo ""
	@echo "Operations:"
	@echo "  make down            - Stop all services"
	@echo "  make restart         - Restart all services"
	@echo "  make clean           - Stop services and remove volumes"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs            - Follow logs from all services"
	@echo "  make status          - Show service status"
	@echo "  make redis-stats     - Show Redis statistics and message counts"
	@echo ""
	@echo "Service-specific logs:"
	@echo "  make logs-korvet     - Follow Korvet logs"
	@echo "  make logs-filebeat   - Follow Filebeat logs"
	@echo "  make logs-logstash   - Follow Logstash logs"
	@echo "  make logs-redis      - Follow Redis logs"
	@echo "  make logs-generator  - Follow log generator logs"
	@echo ""
	@echo "Utilities:"
	@echo "  make redis-cli       - Connect to Redis CLI"
	@echo "  make tail-logs       - Tail the generated log file"
	@echo ""

# Start all services
up:
	docker-compose up -d
	@echo ""
	@echo "Services started! Wait 10-15 seconds for everything to initialize."
	@echo "Then run 'make status' and 'make redis-stats' to verify."

# Stop all services
down:
	docker-compose down

# Restart all services
restart:
	docker-compose restart

# Follow logs from all services
logs:
	docker-compose logs -f

# Service-specific logs
logs-korvet:
	docker-compose logs -f korvet

logs-filebeat:
	docker-compose logs -f filebeat

logs-logstash:
	docker-compose logs -f logstash

logs-redis:
	docker-compose logs -f redis

logs-generator:
	docker-compose logs -f log-generator

# Stop services and remove volumes (clean slate)
clean:
	docker-compose down -v
	@echo "All services stopped and volumes removed."

# Connect to Redis CLI
redis-cli:
	docker-compose exec redis redis-cli

# Show service status
status:
	docker-compose ps

# Show Redis stats
redis-stats:
	@echo "Redis Statistics:"
	@echo "================="
	@docker-compose exec -T redis redis-cli INFO stats | grep -E "total_commands_processed|total_connections_received|instantaneous_ops_per_sec"
	@echo ""
	@echo "Topic Keys:"
	@docker-compose exec -T redis redis-cli KEYS "default:*"
	@echo ""
	@echo "Message Count (partition 0):"
	@docker-compose exec -T redis redis-cli XLEN "default:filebeat-logs:0" 2>/dev/null || echo "0"

# Tail the generated log file
tail-logs:
	docker-compose exec log-generator tail -f /logs/app.log

