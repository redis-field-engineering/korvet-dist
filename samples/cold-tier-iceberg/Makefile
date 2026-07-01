.PHONY: help up down clean catalog-jars produce wait-korvet wait-minio offload-status query-spark logs-korvet logs-minio minio status

TOPIC ?= events
PARTITIONS ?= 2
MESSAGES ?= 20000
KORVET_IMAGE ?= redisfield/korvet:latest
COMPOSE_ENV := TOPIC=$(TOPIC) PARTITIONS=$(PARTITIONS)
COMPOSE := $(COMPOSE_ENV) docker compose

# Spark needs the Iceberg runtime + AWS bundle from Maven, plus Korvet's
# RedisCatalog jar (and its runtime deps) from the Korvet image (see catalog-jars).
SPARK_PACKAGES := org.apache.iceberg:iceberg-spark-runtime-3.5_2.12:1.6.1,org.apache.iceberg:iceberg-aws-bundle:1.6.1,software.amazon.awssdk:bundle:2.27.21

help:
	@echo "Korvet cold-tier Iceberg sample (offload + external query)"
	@echo ""
	@echo "Setup:"
	@echo "  make up            - Start Redis, Korvet (offload->MinIO), MinIO, kafka-tools, Spark"
	@echo "  make catalog-jars  - Extract the RedisCatalog jar + deps from the Korvet image"
	@echo "  make down          - Stop services"
	@echo "  make clean         - Stop services and remove sample data + extracted jars"
	@echo ""
	@echo "Pipeline:"
	@echo "  make produce       - Produce $(MESSAGES) records to '$(TOPIC)' to trigger offload"
	@echo "  make offload-status- Show local vs offloaded segment objects in MinIO"
	@echo "  make query-spark   - Query the Iceberg cold tier with Spark SQL"
	@echo ""
	@echo "Endpoints:"
	@echo "  Korvet Kafka:   localhost:9092"
	@echo "  Korvet health:  http://localhost:8080/actuator/health"
	@echo "  MinIO console:  http://localhost:9001 (minioadmin/minioadmin)"

up:
	$(COMPOSE) up -d redis minio minio-init korvet kafka-tools spark
	@$(MAKE) wait-minio
	@$(MAKE) wait-korvet
	@echo ""
	@echo "Stack is up. Next: make produce && make catalog-jars && make query-spark"

wait-korvet:
	@echo "Waiting for Korvet to accept Kafka connections..."
	@attempt=0; \
	until $(COMPOSE) exec -T kafka-tools /opt/kafka/bin/kafka-topics.sh --bootstrap-server korvet:9092 --list >/dev/null 2>&1; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 30 ]; then echo "Korvet did not become ready in time"; exit 1; fi; \
		sleep 2; \
	done

wait-minio:
	@echo "Waiting for MinIO bucket korvet-cold..."
	@attempt=0; \
	until $(COMPOSE) run --rm --no-deps --entrypoint /bin/sh minio-init -lc 'mc alias set local http://minio:9000 minioadmin minioadmin >/dev/null && mc ls local/korvet-cold >/dev/null'; do \
		attempt=$$((attempt + 1)); \
		if [ "$$attempt" -ge 30 ]; then echo "MinIO bucket korvet-cold was not initialized in time"; exit 1; fi; \
		sleep 1; \
	done

produce:
	@echo "Producing $(MESSAGES) records to '$(TOPIC)' (small segments -> offload)..."
	$(COMPOSE) exec -T kafka-tools sh -lc '\
		seq 1 $(MESSAGES) | \
		awk "{print \"key-\" (\$$1 % 8) \":{\\\"id\\\":\" \$$1 \",\\\"payload\\\":\\\"event-\" \$$1 \"\\\"}\"}" | \
		/opt/kafka/bin/kafka-console-producer.sh \
			--bootstrap-server korvet:9092 \
			--topic $(TOPIC) \
			--property parse.key=true \
			--property key.separator=: ; \
	'
	@echo "Done. The offload worker (tick 10s) will seal and offload segments shortly."

offload-status:
	@echo "Objects under s3://korvet-cold/warehouse (Iceberg cold tier):"
	@$(COMPOSE) run --rm --no-deps --entrypoint /bin/sh minio-init -lc \
		'mc alias set local http://minio:9000 minioadmin minioadmin >/dev/null && mc ls -r local/korvet-cold/ | sed -n "1,40p"'

# Extract the RedisCatalog jar and its runtime dependencies from the Korvet image.
# The published image is a buildpack image; jars are located by name regardless of
# layout. NOTE: the Iceberg jars come from Spark's --packages, so only the Korvet
# catalog jar and its non-Iceberg deps (Lettuce, redis-commons, Gson) are pulled
# here. If you hit a version conflict, align iceberg-spark-runtime in SPARK_PACKAGES
# with the iceberg-core version bundled in the Korvet image.
catalog-jars:
	@mkdir -p catalog-jars
	@echo "Extracting RedisCatalog jar + deps from $(KORVET_IMAGE)..."
	@docker run --rm -v "$$(pwd)/catalog-jars:/out" --entrypoint sh $(KORVET_IMAGE) -c '\
		find / -type f \( \
			-name "korvet-storage-tiered-iceberg*.jar" -o \
			-name "korvet-storage-api*.jar" -o \
			-name "korvet-keyspace*.jar" -o \
			-name "redis-commons*.jar" -o \
			-name "lettuce-core*.jar" -o \
			-name "gson*.jar" -o \
			-name "reactor-core*.jar" -o \
			-name "reactive-streams*.jar" \
		\) -exec cp {} /out/ \; 2>/dev/null'
	@echo "Extracted jars:"
	@ls -1 catalog-jars 2>/dev/null || echo "(none - see README troubleshooting)"

query-spark:
	@if ! ls catalog-jars/*.jar >/dev/null 2>&1; then echo "Run 'make catalog-jars' first."; exit 1; fi
	$(COMPOSE) exec -T spark /opt/spark/bin/spark-submit \
		--master "local[*]" \
		--conf spark.jars.ivy=/tmp/.ivy2 \
		--packages $(SPARK_PACKAGES) \
		--jars "$$($(COMPOSE) exec -T spark sh -lc 'ls /opt/korvet-jars/*.jar | paste -sd, -')" \
		/opt/spark-apps/spark_read_iceberg.py

status:
	@$(COMPOSE) ps
	@curl -s http://localhost:8080/actuator/health 2>/dev/null || echo "Korvet health not ready yet"

minio:
	@open http://localhost:9001 || true

logs-korvet:
	$(COMPOSE) logs -f korvet

logs-minio:
	$(COMPOSE) logs -f minio minio-init

down:
	$(COMPOSE) down

clean:
	$(COMPOSE) down -v
	rm -rf data catalog-jars

.DEFAULT_GOAL := help
