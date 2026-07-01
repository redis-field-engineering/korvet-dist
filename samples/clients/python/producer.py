#!/usr/bin/env python3
"""Standard Kafka producer pointed at Korvet's broker.

Korvet speaks the Kafka wire protocol, so this is an ordinary confluent-kafka
(librdkafka-backed) producer. By default it connects to a Korvet broker on
PLAINTEXT at localhost:9092 with no auth, which works out of the box against
the local stack in ../../kafka-cli.
"""

import json

from confluent_kafka import Producer

BOOTSTRAP_SERVERS = "localhost:9092"
TOPIC = "client-demo"


def build_config():
    config = {
        "bootstrap.servers": BOOTSTRAP_SERVERS,
        "acks": "all",
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


def delivery_report(err, msg):
    if err is not None:
        print(f"Delivery failed for key={msg.key()}: {err}")
        return
    print(f"Sent key={msg.key().decode()} to {msg.topic()}-{msg.partition()}@{msg.offset()}")


def main():
    producer = Producer(build_config())
    for i in range(1, 6):
        key = f"user-{i}"
        value = json.dumps({"id": i, "message": f"Hello from Korvet client {i}"})
        producer.produce(TOPIC, key=key, value=value, callback=delivery_report)
        producer.poll(0)
    producer.flush()
    print(f"Done. Sent 5 records to topic '{TOPIC}'.")


if __name__ == "__main__":
    main()
