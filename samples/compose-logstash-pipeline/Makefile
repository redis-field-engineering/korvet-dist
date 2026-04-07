.PHONY: help up down clean restart logs status topics consume logs-korvet logs-producer logs-consumer describe-topics start-pipeline wait-korvet

PARTITIONS ?= 3
BUCKET_DURATION_MS ?= 60000
LOCAL_RETENTION_MS ?= 300000
RETENTION_MS ?= 86400000

help:
	@echo "Korvet Docker Compose Logstash Pipeline"
	@echo ""
	@echo "Setup:"
	@echo "  make up             - Start services and recreate topics"
	@echo "  make start-pipeline - Start the Logstash producer and consumer"
	@echo "  make down           - Stop services"
	@echo "  make clean          - Stop services and remove local data"
	@echo ""
	@echo "Operations:"
	@echo "  make topics         - Recreate topics with tiered storage settings"
	@echo "  make describe-topics - Describe both topics"
	@echo "  make consume        - Read a few messages from logs-processed"
	@echo "  make status         - Show service status and Korvet health"
	@echo ""
	@echo "Logs:"
	@echo "  make logs           - Follow all logs"
	@echo "  make logs-korvet    - Follow Korvet logs"
	@echo "  make logs-producer  - Follow producer logs"
	@echo "  make logs-consumer  - Follow consumer logs"

up:
	@mkdir -p data/cold
	docker compose up -d redis korvet kafka-tools
	@$(MAKE) wait-korvet
	@$(MAKE) topics
	@$(MAKE) start-pipeline
	@echo ""
	@echo "Pipeline is running:"
	@echo "  Kafka endpoint: localhost:9092"
	@echo "  Korvet health:  http://localhost:8080/actuator/health"
	@echo "  Cold storage:   ./data/cold"

start-pipeline:
	docker compose --profile pipeline up -d logstash-producer logstash-consumer

wait-korvet:
	@echo "Waiting for Korvet to accept Kafka connections..."
	@attempt=0; \
	until docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh --bootstrap-server korvet:9092 --list >/dev/null 2>&1; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 30 ]; then \
			echo "Korvet did not become ready in time"; \
			exit 1; \
		fi; \
		sleep 2; \
	done

down:
	docker compose --profile pipeline down

restart:
	docker compose restart

clean:
	docker compose --profile pipeline down -v
	rm -rf data/cold

logs:
	docker compose logs -f

logs-korvet:
	docker compose logs -f korvet

logs-producer:
	docker compose logs -f logstash-producer

logs-consumer:
	docker compose logs -f logstash-consumer

status:
	@docker compose ps
	@echo ""
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health endpoint is not ready yet"

topics:
	@for topic in logs logs-processed; do \
		echo "Recreating topic $$topic..."; \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 \
			--delete --topic $$topic >/dev/null 2>&1 || true; \
		sleep 2; \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 \
			--create --topic $$topic --partitions $(PARTITIONS); \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-configs.sh \
			--bootstrap-server korvet:9092 \
			--entity-type topics --entity-name $$topic \
			--alter --add-config "bucket.duration.ms=$(BUCKET_DURATION_MS),local.retention.ms=$(LOCAL_RETENTION_MS),retention.ms=$(RETENTION_MS),remote.storage.enable=true"; \
	done

describe-topics:
	@for topic in logs logs-processed; do \
		echo "=== $$topic ==="; \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 --describe --topic $$topic; \
		echo ""; \
	done

consume:
	docker compose exec -T kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 \
		--topic logs-processed \
		--from-beginning \
		--max-messages 10 \
		--timeout-ms 30000

.DEFAULT_GOAL := help
