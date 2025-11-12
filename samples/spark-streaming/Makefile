.PHONY: help up down demo logs clean spark-submit spark-shell redis-cli

# Default target
help:
	@echo "Korvet Spark Streaming Demo - Available Commands"
	@echo "=================================================="
	@echo ""
	@echo "Setup:"
	@echo "  make up           - Start all services"
	@echo "  make down         - Stop all services"
	@echo ""
	@echo "Demo:"
	@echo "  make demo         - Run Spark Streaming application"
	@echo "  make generator    - Start data generator (runs automatically)"
	@echo ""
	@echo "Spark:"
	@echo "  make spark-submit - Submit Spark job manually"
	@echo "  make spark-shell  - Open PySpark shell connected to Korvet"
	@echo "  make spark-ui     - Open Spark Master UI in browser"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs         - View all service logs"
	@echo "  make logs-korvet  - View Korvet logs"
	@echo "  make logs-spark   - View Spark logs"
	@echo "  make logs-gen     - View data generator logs"
	@echo "  make redis-cli    - Connect to Redis CLI"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean        - Stop services and remove all data"
	@echo ""

# Start all services
up:
	@echo "Starting all services..."
	docker compose up -d
	@echo ""
	@echo "Services starting..."
	@echo "  - Redis:          http://localhost:6379"
	@echo "  - Korvet:         http://localhost:9092 (Kafka), http://localhost:8080 (HTTP)"
	@echo "  - Spark Master:   http://localhost:8081"
	@echo "  - Data Generator: Running in background"
	@echo ""
	@echo "Waiting for services to be ready..."
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		if docker compose logs korvet 2>/dev/null | grep -q "Started KorvetApplication"; then \
			echo "✓ All services ready!"; \
			break; \
		fi; \
		sleep 1; \
	done
	@echo ""
	@echo "Next steps:"
	@echo "  1. Run 'make demo' to start Spark Streaming"
	@echo "  2. Open http://localhost:8081 to view Spark UI"
	@echo "  3. Run 'make logs-gen' to see generated events"

# Stop all services
down:
	@echo "Stopping all services..."
	docker compose down

# Run Spark Streaming demo
demo:
	@echo "Starting Spark Streaming application..."
	@echo ""
	docker compose exec spark-master \
		/opt/spark/bin/spark-submit \
		--master spark://spark-master:7077 \
		--packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
		/opt/spark-apps/streaming_reader.py

# Start data generator (already runs automatically)
generator:
	@echo "Data generator is already running in the background."
	@echo "View logs with: make logs-gen"

# Submit Spark job manually
spark-submit:
	@echo "Submitting Spark job..."
	docker compose exec spark-master \
		/opt/spark/bin/spark-submit \
		--master spark://spark-master:7077 \
		--packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0 \
		/opt/spark-apps/streaming_reader.py

# Open PySpark shell
spark-shell:
	@echo "Opening PySpark shell connected to Korvet..."
	@echo "Try: df = spark.readStream.format('kafka').option('kafka.bootstrap.servers', 'korvet:9092').option('subscribe', 'events').load()"
	docker compose exec spark-master \
		/opt/spark/bin/pyspark \
		--master spark://spark-master:7077 \
		--packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0

# Open Spark UI in browser
spark-ui:
	@echo "Opening Spark Master UI..."
	@open http://localhost:8081 || xdg-open http://localhost:8081 || echo "Please open http://localhost:8081 in your browser"

# View all logs
logs:
	docker compose logs -f

# View Korvet logs
logs-korvet:
	docker compose logs -f korvet

# View Spark logs
logs-spark:
	docker compose logs -f spark-master spark-worker

# View data generator logs
logs-gen:
	docker compose logs -f data-generator

# Connect to Redis CLI
redis-cli:
	@echo "Connecting to Redis CLI..."
	@echo "Try: XLEN acme:events:0"
	docker compose exec redis redis-cli

# Clean up everything
clean:
	@echo "Stopping services and removing all data..."
	docker compose down -v
	rm -rf data/
	@echo "✓ Cleanup complete!"

