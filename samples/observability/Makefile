.PHONY: help up down clean logs status load dashboard metrics redis-cli

help:
	@echo "Korvet Observability Sample"
	@echo ""
	@echo "Setup:"
	@echo "  make up         - Start Redis, Korvet, Prometheus, Grafana"
	@echo "  make down       - Stop all services"
	@echo "  make clean      - Stop services and remove volumes"
	@echo "  make logs       - Tail logs from all services"
	@echo "  make status     - Show service status and Korvet health"
	@echo ""
	@echo "Demo:"
	@echo "  make load       - Generate produce/consume load to populate the dashboard"
	@echo "  make dashboard  - Open the Grafana dashboard"
	@echo "  make metrics    - Open Prometheus"
	@echo "  make redis-cli  - Connect to the Redis CLI"

up:
	@echo "Starting observability stack..."
	docker compose up -d
	@echo ""
	@echo "Korvet:     localhost:9092 (Kafka), http://localhost:8080 (actuator)"
	@echo "Prometheus: http://localhost:9090"
	@echo "Grafana:    http://localhost:3000 (anonymous admin, no login)"
	@echo ""
	@echo "Run 'make load' to generate traffic, then 'make dashboard'."

down:
	docker compose down

clean:
	docker compose down -v

logs:
	docker compose logs -f

status:
	@docker compose ps
	@echo ""
	@echo "Korvet health:"
	@curl -s http://localhost:8080/actuator/health || echo "Korvet not ready"

load:
	@echo "Producing 500K messages and consuming them back (watch the dashboard)..."
	docker compose exec kafka-tools kafka-producer-perf-test \
		--topic observability-demo \
		--num-records 500000 \
		--record-size 1024 \
		--throughput 20000 \
		--producer-props bootstrap.servers=korvet:9092
	docker compose exec kafka-tools kafka-consumer-perf-test \
		--topic observability-demo \
		--messages 500000 \
		--bootstrap-server korvet:9092 \
		--group observability-demo

dashboard:
	@echo "Opening Grafana: http://localhost:3000"
	@open http://localhost:3000 || xdg-open http://localhost:3000 || echo "Open http://localhost:3000 in your browser"

metrics:
	@echo "Opening Prometheus: http://localhost:9090"
	@open http://localhost:9090 || xdg-open http://localhost:9090 || echo "Open http://localhost:9090 in your browser"

redis-cli:
	docker compose exec redis redis-cli

.DEFAULT_GOAL := help
