#!/bin/bash
#
# Data Generator for Spark Streaming Demo
# Produces sample e-commerce events to Korvet
#

set -e

KAFKA_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP_SERVERS:-korvet:9092}"
TOPIC="events"
EVENTS_PER_BATCH=10
BATCH_INTERVAL=5  # seconds

echo "=========================================="
echo "Korvet Data Generator"
echo "=========================================="
echo "Bootstrap servers: $KAFKA_BOOTSTRAP_SERVERS"
echo "Topic: $TOPIC"
echo "Events per batch: $EVENTS_PER_BATCH"
echo "Batch interval: ${BATCH_INTERVAL}s"
echo "=========================================="
echo ""

# Wait for Korvet to be ready
echo "Waiting for Korvet to be ready..."
sleep 10

# Event types
EVENT_TYPES=("page_view" "add_to_cart" "purchase" "search" "click")
PRODUCTS=("laptop" "phone" "tablet" "headphones" "keyboard" "mouse" "monitor" "camera")

# Function to generate random event
# Returns: key|value format for kafka-console-producer
generate_event() {
    local event_id="evt_$(date +%s%N | cut -b1-13)"
    local user_id="user_$((RANDOM % 1000))"
    local event_type="${EVENT_TYPES[$((RANDOM % ${#EVENT_TYPES[@]}))]}"
    local product_id="${PRODUCTS[$((RANDOM % ${#PRODUCTS[@]}))]}"
    local price=$(awk -v min=10 -v max=2000 'BEGIN{srand(); print min+rand()*(max-min)}')
    local timestamp=$(date +%s)000

    # Return key|value format (user_id as key for partitioning)
    echo "$user_id|{\"event_id\":\"$event_id\",\"user_id\":\"$user_id\",\"event_type\":\"$event_type\",\"product_id\":\"$product_id\",\"price\":$price,\"timestamp\":$timestamp}"
}

# Generate and send events continuously
batch_num=0
total_events=0

echo "Starting event generation..."
echo ""

while true; do
    batch_num=$((batch_num + 1))
    echo "[Batch $batch_num] Generating $EVENTS_PER_BATCH events..."

    for i in $(seq 1 $EVENTS_PER_BATCH); do
        event=$(generate_event)
        echo "$event" | /opt/kafka/bin/kafka-console-producer.sh \
            --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" \
            --topic "$TOPIC" \
            --property "parse.key=true" \
            --property "key.separator=|" \
            --producer-property enable.idempotence=false \
            2>/dev/null

        total_events=$((total_events + 1))
    done

    echo "[Batch $batch_num] Sent $EVENTS_PER_BATCH events (Total: $total_events)"
    echo ""

    sleep $BATCH_INTERVAL
done

