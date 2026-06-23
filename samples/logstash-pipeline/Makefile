.PHONY: help up down clean restart logs status topics consume logs-korvet logs-producer logs-consumer describe-topics start-pipeline wait-korvet prepare reset-storage flush-redis show-config verify-cold-storage

# Topic names are fixed by producer.conf and consumer.conf.
SOURCE_TOPIC := logs
PROCESSED_TOPIC := logs-processed
PRODUCER_SERVICES := logstash-producer
CONSUMER_SERVICES := logstash-consumer
PARTITIONS ?= 4
RETENTION_MS ?= 86400000
REDIS_MAXMEMORY_BYTES ?= 268435456
LOCAL_RETENTION_BYTES ?= $(shell expr $(REDIS_MAXMEMORY_BYTES) \* 80 / 100)
REDIS_PORT ?= 12000

# Remote (tiered) storage is opt-in. Leave REMOTE_STORAGE_PATH empty for
# hot-tier-only storage, or set it (e.g. s3://korvet/cold) to enable
# MinIO-backed cold storage via docker-compose.tiered.yml.
REMOTE_STORAGE_PATH ?=

# COMPOSE_ALL always includes the tiered overlay so teardown targets remove
# MinIO containers left over from a tiered run even when REMOTE_STORAGE_PATH
# is unset.
COMPOSE_ALL := docker compose -f docker-compose.yml -f docker-compose.tiered.yml

ifneq ($(REMOTE_STORAGE_PATH),)
export REMOTE_STORAGE_PATH
COMPOSE := $(COMPOSE_ALL)
SOURCE_TOPIC_CONFIG := retention.ms=$(RETENTION_MS),local.retention.bytes=$(LOCAL_RETENTION_BYTES),remote.storage.enable=true
else
COMPOSE := docker compose
SOURCE_TOPIC_CONFIG := retention.ms=$(RETENTION_MS),local.retention.bytes=$(LOCAL_RETENTION_BYTES)
endif

help:
	@echo "Korvet Docker Compose Logstash Pipeline"
	@echo ""
	@echo "Setup:"
	@echo "  make up             - Reset storage, start services, ensure topics/configs, and start the Logstash producer and consumer"
	@echo "  make start-pipeline - Start the Logstash producer and consumer"
	@echo "  make down           - Stop services"
	@echo "  make clean          - Stop services and remove local data"
	@echo ""
	@echo "Storage:"
	@echo "  By default Korvet runs with hot-tier (Redis) storage only."
	@echo "  Set REMOTE_STORAGE_PATH to enable MinIO-backed cold storage, e.g.:"
	@echo "    make up REMOTE_STORAGE_PATH=s3://korvet/cold"
	@echo ""
	@echo "Operations:"
	@echo "  make topics         - Ensure topics exist with retention settings"
	@echo "  make describe-topics - Describe the topics"
	@echo "  make consume        - Read a few messages from logs-processed"
	@echo "  make verify-cold-storage - Verify cold-storage files exist in MinIO data (tiered mode only)"
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
ifneq ($(REMOTE_STORAGE_PATH),)
	$(COMPOSE) up -d minio minio-init
endif
	$(COMPOSE) up -d korvet kafka-tools
	@$(MAKE) wait-korvet
	@$(MAKE) topics
	@$(MAKE) start-pipeline
	@echo ""
	@echo "Pipeline is running:"
	@echo "  Kafka endpoint: localhost:9092"
	@echo "  Korvet health:  http://localhost:8080/actuator/health"
ifneq ($(REMOTE_STORAGE_PATH),)
	@echo "  Remote storage: $(REMOTE_STORAGE_PATH)"
	@echo "  S3 endpoint:    http://localhost:9000"
	@echo "  MinIO console:  http://localhost:9001"
endif

start-pipeline:
	$(COMPOSE) --profile pipeline up -d $(PRODUCER_SERVICES) $(CONSUMER_SERVICES)

prepare: reset-storage
ifneq ($(REMOTE_STORAGE_PATH),)
	@mkdir -p data/minio
endif

reset-storage:
	@$(COMPOSE_ALL) --profile pipeline down -v >/dev/null 2>&1 || true
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
	until $(COMPOSE) exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh --bootstrap-server korvet:9092 --list >/dev/null 2>&1; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 30 ]; then \
			echo "Korvet did not become ready in time"; \
			exit 1; \
		fi; \
		sleep 2; \
	done

down:
	$(COMPOSE_ALL) --profile pipeline down

restart:
	$(COMPOSE) --profile pipeline restart

clean:
	$(COMPOSE_ALL) --profile pipeline down -v
	rm -rf data/minio

logs:
	$(COMPOSE) --profile pipeline logs -f

logs-korvet:
	$(COMPOSE) logs -f korvet

logs-producer:
	$(COMPOSE) logs -f $(PRODUCER_SERVICES)

logs-consumer:
	$(COMPOSE) logs -f $(CONSUMER_SERVICES)

status:
	@$(COMPOSE) --profile pipeline ps
	@echo ""
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health endpoint is not ready yet"

topics:
	@$(COMPOSE) exec -T kafka-tools sh -lc '\
		echo "Ensuring topic $(SOURCE_TOPIC)..."; \
		/opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 \
			--create --if-not-exists --topic $(SOURCE_TOPIC) --partitions $(PARTITIONS); \
		/opt/kafka/bin/kafka-configs.sh \
			--bootstrap-server korvet:9092 \
			--entity-type topics --entity-name $(SOURCE_TOPIC) \
			--alter --add-config "$(SOURCE_TOPIC_CONFIG)"; \
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
	@for topic in $(SOURCE_TOPIC) $(PROCESSED_TOPIC); do \
		echo "=== $$topic ==="; \
		$(COMPOSE) exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 --describe --topic $$topic; \
		echo ""; \
	done

consume:
	$(COMPOSE) exec -T kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 \
		--topic $(PROCESSED_TOPIC) \
		--from-beginning \
		--max-messages 10 \
		--timeout-ms 30000

verify-cold-storage:
	@if [ -z "$(REMOTE_STORAGE_PATH)" ]; then \
		echo "Remote storage is disabled. Re-run with REMOTE_STORAGE_PATH set, e.g. REMOTE_STORAGE_PATH=s3://korvet/cold"; \
		exit 1; \
	fi
	@COLD_ROOT="data/minio/korvet/cold"; \
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
	@echo "Remote storage path:      $(if $(REMOTE_STORAGE_PATH),$(REMOTE_STORAGE_PATH),(disabled))"
	@echo "Redis maxmemory bytes:    $(REDIS_MAXMEMORY_BYTES)"
	@echo "Suggested local retention bytes (80%): $(LOCAL_RETENTION_BYTES)"

.DEFAULT_GOAL := help
