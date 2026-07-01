#!/usr/bin/env python3
"""Standard Kafka consumer pointed at Korvet's broker.

Korvet supports consumer groups and offset commit just like Kafka. This
example joins a group, subscribes to a topic, polls in a loop, and commits
offsets manually (enable.auto.commit=False) after processing each message.

By default it connects to a Korvet broker on PLAINTEXT at localhost:9092 with
no auth, which works out of the box against the local stack in ../../kafka-cli.
"""

from confluent_kafka import Consumer, KafkaError

BOOTSTRAP_SERVERS = "localhost:9092"
TOPIC = "client-demo"
GROUP_ID = "client-demo-group"


def build_config():
    config = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "group.id": GROUP_ID,
        # Start from the beginning when the group has no committed offset.
        "auto.offset.reset": "earliest",
        # Manual commit: disable auto-commit and call commit() ourselves.
        "enable.auto.commit": False,
    }

    # -------------------------------------------------------------------------
    # SASL_SSL configuration (disabled by default).
    #
    # Uncomment to connect to a Korvet broker that has SASL and TLS enabled
    # (KORVET_BROKER_SASL_ENABLED=true, KORVET_BROKER_TLS=true). Korvet's
    # default mechanism is SCRAM-SHA-256. PLAIN is also supported but PLAIN
    # requires TLS.
    #
    # config.update({
    #     "security.protocol": "SASL_SSL",
    #     "sasl.mechanism": "SCRAM-SHA-256",
    #     "sasl.username": "alice",
    #     "sasl.password": "alice-secret",
    #     "ssl.ca.location": "/path/to/ca.pem",
    # })
    # -------------------------------------------------------------------------

    return config


def main():
    consumer = Consumer(build_config())
    consumer.subscribe([TOPIC])
    print(f"Subscribed to '{TOPIC}' as group '{GROUP_ID}'. Ctrl-C to stop.")
    try:
        while True:
            msg = consumer.poll(1.0)
            if msg is None:
                continue
            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    continue
                print(f"Consumer error: {msg.error()}")
                continue
            key = msg.key().decode() if msg.key() is not None else None
            value = msg.value().decode() if msg.value() is not None else None
            print(f"Received key={key} value={value} "
                  f"({msg.topic()}-{msg.partition()}@{msg.offset()})")
            # Commit the offset only after the message has been processed.
            consumer.commit(message=msg, asynchronous=False)
    except KeyboardInterrupt:
        print("\nStopping.")
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
