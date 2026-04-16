#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SAMPLE_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

TOPIC_PREFIX=${TOPIC_PREFIX:-logs}
TOPIC_COUNT=${TOPIC_COUNT:-10}

GENERATED_DIR="$SAMPLE_DIR/.generated"
PRODUCER_DIR="$GENERATED_DIR/producer"
CONSUMER_DIR="$GENERATED_DIR/consumer"
PRODUCER_TEMPLATE="$SAMPLE_DIR/templates/producer.conf.tmpl"
CONSUMER_TEMPLATE="$SAMPLE_DIR/templates/consumer.conf.tmpl"

rm -rf "$GENERATED_DIR"
mkdir -p "$PRODUCER_DIR" "$CONSUMER_DIR"

consumer_pipelines="$CONSUMER_DIR/pipelines.yml"
producer_pipelines="$PRODUCER_DIR/pipelines.yml"
: >"$consumer_pipelines"
: >"$producer_pipelines"

i=1
while [ "$i" -le "$TOPIC_COUNT" ]; do
  topic=$(printf "%s-%02d" "$TOPIC_PREFIX" "$i")
  producer_conf="$PRODUCER_DIR/$topic.conf"
  consumer_conf="$CONSUMER_DIR/$topic.conf"

  sed "s/__TOPIC__/$topic/g" "$PRODUCER_TEMPLATE" >"$producer_conf"
  sed "s/__TOPIC__/$topic/g" "$CONSUMER_TEMPLATE" >"$consumer_conf"

  cat >>"$producer_pipelines" <<EOF
- pipeline.id: producer-$topic
  path.config: /usr/share/logstash/pipeline/$topic.conf
EOF

  cat >>"$consumer_pipelines" <<EOF
- pipeline.id: consumer-$topic
  path.config: /usr/share/logstash/pipeline/$topic.conf
EOF

  i=$((i + 1))
done
