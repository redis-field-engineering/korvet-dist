.PHONY: help up down clean logs logs-connect logs-producer status topics consume-kafka produce-once tail-output show-output redis-cli

TOPIC ?= dw-scte

help:
	@echo "Korvet Kafka Connect File Sink Sample"
	@echo ""
	@echo "Setup:"
	@echo "  make up             - Build the Connect image and start all services"
	@echo "  make down           - Stop all services"
	@echo "  make clean          - Stop services and remove volumes"
	@echo ""
	@echo "Demo:"
	@echo "  make produce-once   - Produce one JSON event to Kafka topic $(TOPIC)"
	@echo "  make consume-kafka  - Consume events directly from Korvet/Kafka"
	@echo "  make tail-output    - Tail the file sink output"
	@echo "  make show-output    - Show the last records written by Kafka Connect"
	@echo ""
	@echo "Monitoring:"
	@echo "  make status         - Show service status"
	@echo "  make topics         - List Kafka topics"
	@echo "  make logs           - Follow all logs"
	@echo "  make logs-connect   - Follow Kafka Connect logs"
	@echo "  make logs-producer  - Follow event producer logs"
	@echo "  make redis-cli      - Connect to Korvet Redis"

up:
	mkdir -p output
	docker compose up -d
	@echo ""
	@echo "Services are starting."
	@echo "Kafka endpoint on host: localhost:19092"
	@echo "Korvet health on host: http://localhost:18080/actuator/health"

down:
	docker compose down

clean:
	docker compose down -v
	rm -rf output

logs:
	docker compose logs -f

logs-connect:
	docker compose logs -f kafka-connect

logs-producer:
	docker compose logs -f event-producer

status:
	docker compose ps

topics:
	docker compose exec kafka-tools /opt/kafka/bin/kafka-topics.sh \
		--bootstrap-server korvet:9092 \
		--list

consume-kafka:
	docker compose exec kafka-tools /opt/kafka/bin/kafka-console-consumer.sh \
		--bootstrap-server korvet:9092 \
		--topic $(TOPIC) \
		--from-beginning

produce-once:
	@printf '%s\n' '{"event_id":"manual","source":"make","segmentation_type":"provider_ad_start"}' | \
		docker compose exec -T kafka-tools /opt/kafka/bin/kafka-console-producer.sh \
			--bootstrap-server korvet:9092 \
			--topic $(TOPIC) \
			--producer-property enable.idempotence=false

tail-output:
	mkdir -p output
	touch output/dw-scte.jsonl
	tail -f output/dw-scte.jsonl

show-output:
	@tail -20 output/dw-scte.jsonl 2>/dev/null || echo "No output yet. Run 'make up' and wait for Connect to consume records."

redis-cli:
	docker compose exec korvet-redis redis-cli
