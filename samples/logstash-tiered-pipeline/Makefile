.PHONY: help up down clean restart logs status topics consume logs-korvet logs-producer logs-consumer describe-topics start-pipeline wait-korvet prepare reset-storage flush-redis show-config

TOPIC_COUNT ?= 10
TOPIC_PREFIX ?= logs
PROCESSED_TOPIC ?= logs-processed
PARTITIONS ?= 4
BUCKET_DURATION_MS ?= 60000
RETENTION_MS ?= 86400000
REDIS_MAXMEMORY_BYTES ?= 268435456
LOCAL_RETENTION_BYTES ?= $(shell expr $(REDIS_MAXMEMORY_BYTES) \* 80 / 100)
REDIS_PORT ?= 12000

help:
	@echo "Korvet Docker Compose Logstash Pipeline"
	@echo ""
	@echo "Setup:"
	@echo "  make up             - Reset storage, start services, and recreate topics"
	@echo "  make start-pipeline - Start the Logstash producer and consumer"
	@echo "  make down           - Stop services"
	@echo "  make clean          - Stop services and remove local data"
	@echo ""
	@echo "Operations:"
	@echo "  make topics         - Recreate topics with tiered storage settings"
	@echo "  make describe-topics - Describe all source topics"
	@echo "  make consume        - Read a few messages from logs-processed"
	@echo "  make show-config    - Show computed retention settings"
	@echo "  make status         - Show service status and Korvet health"
	@echo ""
	@echo "Logs:"
	@echo "  make logs           - Follow all logs"
	@echo "  make logs-korvet    - Follow Korvet logs"
	@echo "  make logs-producer  - Follow producer logs"
	@echo "  make logs-consumer  - Follow consumer logs"

up:
	@$(MAKE) prepare
	@$(MAKE) flush-redis
	docker compose up -d minio minio-init
	docker compose up -d korvet kafka-tools
	@$(MAKE) wait-korvet
	@$(MAKE) topics
	@$(MAKE) start-pipeline
	@echo ""
	@echo "Pipeline is running:"
	@echo "  Kafka endpoint: localhost:9092"
	@echo "  Korvet health:  http://localhost:8080/actuator/health"
	@echo "  S3 endpoint:    http://localhost:9000"
	@echo "  MinIO console:  http://localhost:9001"

start-pipeline:
	docker compose --profile pipeline up -d logstash-producer logstash-consumer

prepare: reset-storage
	@mkdir -p data/minio

reset-storage:
	@docker compose --profile pipeline down -v >/dev/null 2>&1 || true
	rm -rf data/minio

flush-redis:
	@echo "Flushing Redis Enterprise DB on localhost:$(REDIS_PORT)..."
	@attempt=0; \
	until redis-cli -p $(REDIS_PORT) FLUSHALL >/dev/null 2>&1; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 15 ]; then \
			echo "Redis Enterprise DB on localhost:$(REDIS_PORT) did not respond in time"; \
			exit 1; \
		fi; \
		sleep 1; \
	done

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
	docker compose --profile pipeline restart

clean:
	docker compose --profile pipeline down -v
	rm -rf data/minio

logs:
	docker compose --profile pipeline logs -f

logs-korvet:
	docker compose logs -f korvet

logs-producer:
	docker compose logs -f logstash-producer

logs-consumer:
	docker compose logs -f logstash-consumer

status:
	@docker compose --profile pipeline ps
	@echo ""
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health endpoint is not ready yet"

topics:
	@for topic in $$(seq -f "$(TOPIC_PREFIX)-%02g" 1 $(TOPIC_COUNT)); do \
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
			--alter --add-config "bucket.duration.ms=$(BUCKET_DURATION_MS),retention.ms=$(RETENTION_MS),remote.storage.enable=true"; \
	done
	@docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 \
		--delete --topic $(PROCESSED_TOPIC) >/dev/null 2>&1 || true
	@sleep 2
	@docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 \
		--create --topic $(PROCESSED_TOPIC) --partitions $(PARTITIONS)

describe-topics:
	@for topic in $$(seq -f "$(TOPIC_PREFIX)-%02g" 1 $(TOPIC_COUNT)) $(PROCESSED_TOPIC); do \
		echo "=== $$topic ==="; \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 --describe --topic $$topic; \
		echo ""; \
	done

consume:
	docker compose exec -T kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 \
		--topic $(PROCESSED_TOPIC) \
		--from-beginning \
		--max-messages 10 \
		--timeout-ms 30000

show-config:
	@echo "Redis maxmemory bytes:    $(REDIS_MAXMEMORY_BYTES)"
	@echo "Suggested local retention bytes (80%): $(LOCAL_RETENTION_BYTES)"
	@echo "Topic count:              $(TOPIC_COUNT)"

.DEFAULT_GOAL := help
