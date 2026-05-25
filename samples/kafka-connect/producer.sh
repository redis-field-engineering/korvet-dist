#!/bin/sh
set -eu

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-korvet:9092}"
TOPIC="${TOPIC:-dw-scte}"

until /opt/kafka/bin/kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVER" --list >/dev/null 2>&1; do
  echo "Waiting for Korvet at $BOOTSTRAP_SERVER..."
  sleep 2
done

/opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --create --if-not-exists \
  --topic "$TOPIC" \
  --partitions 1

i=0
while true; do
  i=$((i + 1))
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  splice_event_id=$(printf "0x%08x" "$i")
  segmentation_type=$(printf "provider_ad_start\nprovider_ad_end\nprogram_start\nprogram_end" | shuf -n 1)
  printf '{"event_id":%d,"timestamp":"%s","splice_event_id":"%s","segmentation_type":"%s"}\n' "$i" "$timestamp" "$splice_event_id" "$segmentation_type"
  sleep 2
done | /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server "$BOOTSTRAP_SERVER" \
  --topic "$TOPIC" \
  --producer-property enable.idempotence=false
