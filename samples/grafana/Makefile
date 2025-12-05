.PHONY: up down logs producer-logs consumer-logs dashboard clean

# Default producer rate (messages per second)
PRODUCER_RATE ?= 1000

up:
	PRODUCER_RATE=$(PRODUCER_RATE) docker compose up -d

down:
	docker compose down

logs:
	docker compose logs -f

producer-logs:
	docker compose logs -f load-generator-producer

consumer-logs:
	docker compose logs -f load-generator-consumer

dashboard:
	open http://localhost:3000

clean:
	docker compose down -v
