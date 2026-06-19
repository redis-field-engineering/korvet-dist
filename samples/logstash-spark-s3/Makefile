.PHONY: help up down clean logs logs-korvet logs-logstash logs-spark logs-prometheus logs-minio status wait-korvet wait-minio topics start-producer stop-producer spark-submit spark-submit-bg read-delta prometheus minio

TOPIC ?= logs
PARTITIONS ?= 4
RETENTION_MS ?= 86400000
SPARK_PACKAGES := org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0,io.delta:delta-spark_2.12:3.2.0,org.apache.hadoop:hadoop-aws:3.3.4
COMPOSE_ENV := TOPIC=$(TOPIC) PARTITIONS=$(PARTITIONS) RETENTION_MS=$(RETENTION_MS)
COMPOSE := $(COMPOSE_ENV) docker compose

help:
	@echo "Korvet Logstash Spark S3 Delta sample"
	@echo ""
	@echo "Setup:"
	@echo "  make up              - Start Redis, Korvet, MinIO, Prometheus, Spark, create topic, and start Logstash"
	@echo "  make down            - Stop services"
	@echo "  make clean           - Stop services and remove sample data"
	@echo ""
	@echo "Pipeline:"
	@echo "  make spark-submit    - Run Spark consumer and write Delta analytics to MinIO S3"
	@echo "  make spark-submit-bg - Run Spark consumer in the background"
	@echo "  make read-delta      - Read a sample of the Delta latency analytics table"
	@echo "  make start-producer  - Start only the Logstash producer"
	@echo "  make stop-producer   - Stop only the Logstash producer"
	@echo ""
	@echo "Endpoints:"
	@echo "  Korvet Kafka:        localhost:9092"
	@echo "  Korvet Prometheus:   http://localhost:8080/actuator/prometheus"
	@echo "  Prometheus:          http://localhost:9090"
	@echo "  MinIO console:       http://localhost:9001 (minioadmin/minioadmin)"
	@echo "  Spark master UI:     http://localhost:8081"

up:
	$(COMPOSE) up -d redis korvet kafka-tools minio minio-init prometheus spark-master spark-worker
	@$(MAKE) wait-korvet
	@$(MAKE) wait-minio
	@$(MAKE) topics
	@$(MAKE) start-producer
	@echo ""
	@echo "Stack is running. Start the Delta writer with: make spark-submit"

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

wait-minio:
	@echo "Waiting for MinIO bucket initialization..."
	@attempt=0; \
	until $(COMPOSE) run --rm --no-deps --entrypoint /bin/sh minio-init -lc 'mc alias set local http://minio:9000 minioadmin minioadmin >/dev/null && mc ls local/korvet-analytics >/dev/null'; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 30 ]; then \
			echo "MinIO bucket korvet-analytics was not initialized in time"; \
			exit 1; \
		fi; \
		sleep 1; \
	done

topics:
	$(COMPOSE) exec -T kafka-tools sh -lc '\
		/opt/kafka/bin/kafka-topics.sh \
			--bootstrap-server korvet:9092 \
			--create --if-not-exists --topic $(TOPIC) --partitions $(PARTITIONS) \
			--config retention.ms=$(RETENTION_MS) \
			--config log.append.timestamp.header=true; \
		/opt/kafka/bin/kafka-configs.sh \
			--bootstrap-server korvet:9092 \
			--entity-type topics --entity-name $(TOPIC) \
			--alter --add-config "retention.ms=$(RETENTION_MS),log.append.timestamp.header=true"; \
	'

start-producer:
	$(COMPOSE) --profile pipeline up -d logstash-producer

stop-producer:
	$(COMPOSE) stop logstash-producer

spark-submit:
	$(COMPOSE) exec -T \
			spark-master /opt/spark/bin/spark-submit \
			--master spark://spark-master:7077 \
		--conf spark.jars.ivy=/tmp/.ivy2 \
		--packages $(SPARK_PACKAGES) \
		/opt/spark-apps/spark_consumer.py

spark-submit-bg:
	$(COMPOSE) exec -T -d \
			spark-master /opt/spark/bin/spark-submit \
			--master spark://spark-master:7077 \
		--conf spark.jars.ivy=/tmp/.ivy2 \
		--packages $(SPARK_PACKAGES) \
		/opt/spark-apps/spark_consumer.py

read-delta:
	$(COMPOSE) exec -T spark-master /opt/spark/bin/spark-submit \
		--master "local[*]" \
		--conf spark.jars.ivy=/tmp/.ivy2 \
		--packages $(SPARK_PACKAGES) \
		/opt/spark-apps/read_delta.py

status:
	@$(COMPOSE) --profile pipeline ps
	@echo ""
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health endpoint is not ready yet"
	@echo ""
	@curl -s http://localhost:8080/actuator/prometheus 2>/dev/null | sed -n '1,12p' || true

prometheus:
	@open http://localhost:9090 || true

minio:
	@open http://localhost:9001 || true

logs:
	$(COMPOSE) --profile pipeline logs -f

logs-korvet:
	$(COMPOSE) logs -f korvet

logs-logstash:
	$(COMPOSE) logs -f logstash-producer

logs-spark:
	$(COMPOSE) logs -f spark-master spark-worker

logs-prometheus:
	$(COMPOSE) logs -f prometheus

logs-minio:
	$(COMPOSE) logs -f minio minio-init

down:
	$(COMPOSE) --profile pipeline down

clean:
	$(COMPOSE) --profile pipeline down -v
	rm -rf data

.DEFAULT_GOAL := help
