.PHONY: help up down clean restart logs status topics consume logs-korvet logs-producer logs-consumer describe-topics start-pipeline wait-korvet prepare reset-storage flush-redis show-config render-pipelines verify-cold-storage

TOPIC_COUNT ?= 10
TOPIC_PREFIX ?= logs
PROCESSED_TOPIC ?= logs-processed
SOURCE_TOPICS := $(shell seq -f "$(TOPIC_PREFIX)-%02g" 1 $(TOPIC_COUNT))
PRODUCER_SERVICES := logstash-producer
CONSUMER_SERVICES := logstash-consumer
PARTITIONS ?= 4
RETENTION_MS ?= 86400000
REDIS_MAXMEMORY_BYTES ?= 268435456
LOCAL_RETENTION_BYTES ?= $(shell expr $(REDIS_MAXMEMORY_BYTES) \* 80 / 100)
REDIS_PORT ?= 12000

help:
	@echo "Korvet Docker Compose Logstash Pipeline"
	@echo ""
	@echo "Setup:"
	@echo "  make up             - Reset storage, start services, ensure topics/configs, and start multi-pipeline Logstash producer and consumer"
	@echo "  make start-pipeline - Start the multi-pipeline Logstash producer and consumer"
	@echo "  make down           - Stop services"
	@echo "  make clean          - Stop services and remove local data"
	@echo ""
	@echo "Operations:"
	@echo "  make topics         - Ensure topics exist with tiered storage settings"
	@echo "  make describe-topics - Describe all source topics"
	@echo "  make consume        - Read a few messages from logs-processed"
	@echo "  make verify-cold-storage - Verify cold-storage files exist in MinIO data"
	@echo "  make show-config    - Show computed retention settings"
	@echo "  make status         - Show service status and Korvet health"
	@echo ""
	@echo "Logs:"
	@echo "  make logs           - Follow all logs"
	@echo "  make logs-korvet    - Follow Korvet logs"
	@echo "  make logs-producer  - Follow the Logstash producer logs"
	@echo "  make logs-consumer  - Follow the Logstash consumer logs"

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
	docker compose --profile pipeline up -d $(PRODUCER_SERVICES) $(CONSUMER_SERVICES)

prepare: reset-storage
	@mkdir -p data/minio
	@$(MAKE) render-pipelines

render-pipelines:
	@./scripts/render-pipelines.sh

reset-storage:
	@docker compose --profile pipeline down -v >/dev/null 2>&1 || true
	rm -rf data/minio
	rm -rf .generated

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
	docker compose logs -f $(PRODUCER_SERVICES)

logs-consumer:
	docker compose logs -f $(CONSUMER_SERVICES)

status:
	@docker compose --profile pipeline ps
	@echo ""
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health endpoint is not ready yet"

topics:
	@docker compose exec -T kafka-tools sh -lc '\
		for topic in $(SOURCE_TOPICS); do \
			echo "Ensuring topic $$topic..."; \
			/opt/kafka/bin/kafka-topics.sh \
				--bootstrap-server korvet:9092 \
				--create --if-not-exists --topic $$topic --partitions $(PARTITIONS); \
			/opt/kafka/bin/kafka-configs.sh \
				--bootstrap-server korvet:9092 \
				--entity-type topics --entity-name $$topic \
				--alter --add-config "retention.ms=$(RETENTION_MS),local.retention.bytes=$(LOCAL_RETENTION_BYTES),remote.storage.enable=true"; \
		done; \
		echo "Ensuring topic $(PROCESSED_TOPIC)..."; \
		/opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 \
			--create --if-not-exists --topic $(PROCESSED_TOPIC) --partitions $(PARTITIONS); \
		/opt/kafka/bin/kafka-configs.sh \
			--bootstrap-server korvet:9092 \
			--entity-type topics --entity-name $(PROCESSED_TOPIC) \
			--alter --add-config "local.retention.bytes=$(LOCAL_RETENTION_BYTES)"; \
	'

describe-topics:
	@for topic in $(SOURCE_TOPICS) $(PROCESSED_TOPIC); do \
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

verify-cold-storage:
	@COLD_ROOT="data/minio/korvet/delta"; \
	if [ ! -d "$$COLD_ROOT" ]; then \
		echo "Cold storage directory $$COLD_ROOT does not exist"; \
		exit 1; \
	fi; \
	COUNT=$$(find "$$COLD_ROOT" -type f | wc -l | tr -d ' '); \
	if [ "$$COUNT" -eq 0 ]; then \
		echo "No cold-storage files found under $$COLD_ROOT"; \
		exit 1; \
	fi; \
	echo "Found $$COUNT cold-storage files under $$COLD_ROOT"; \
	find "$$COLD_ROOT" -type f | sed -n '1,10p'

show-config:
	@echo "Redis maxmemory bytes:    $(REDIS_MAXMEMORY_BYTES)"
	@echo "Suggested local retention bytes (80%): $(LOCAL_RETENTION_BYTES)"
	@echo "Topic count:              $(TOPIC_COUNT)"

.DEFAULT_GOAL := help
