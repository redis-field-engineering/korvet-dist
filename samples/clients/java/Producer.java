import java.util.Properties;
import java.util.concurrent.ExecutionException;
import java.util.stream.IntStream;

import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.apache.kafka.common.serialization.StringSerializer;

/**
 * Standard Kafka producer pointed at Korvet's broker.
 *
 * Korvet speaks the Kafka wire protocol, so this is an ordinary
 * org.apache.kafka:kafka-clients producer. By default it connects to a
 * Korvet broker listening on PLAINTEXT at localhost:9092 with no auth, which
 * works out of the box against the local stack in ../../kafka-cli.
 */
public final class Producer {

    private static final String BOOTSTRAP_SERVERS = "localhost:9092";
    private static final String TOPIC = "client-demo";

    private Producer() {
    }

    public static void main(String[] args) throws InterruptedException, ExecutionException {
        Properties props = new Properties();
        props.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
        props.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        props.put(ProducerConfig.ACKS_CONFIG, "all");

        // ---------------------------------------------------------------------
        // SASL_SSL configuration (disabled by default).
        //
        // Uncomment this block to connect to a Korvet broker that has SASL and
        // TLS enabled (KORVET_BROKER_SASL_ENABLED=true, KORVET_BROKER_TLS=true).
        // Korvet's default mechanism is SCRAM-SHA-256. PLAIN is also supported
        // but PLAIN requires TLS.
        //
        // props.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        // props.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-256");
        // props.put(SaslConfigs.SASL_JAAS_CONFIG,
        //         "org.apache.kafka.common.security.scram.ScramLoginModule required "
        //                 + "username=\"alice\" password=\"alice-secret\";");
        // props.put(SslConfigs.SSL_TRUSTSTORE_LOCATION_CONFIG, "/path/to/truststore.jks");
        // props.put(SslConfigs.SSL_TRUSTSTORE_PASSWORD_CONFIG, "changeit");
        //
        // Add these imports when enabling the block above:
        //   import org.apache.kafka.clients.CommonClientConfigs;
        //   import org.apache.kafka.common.config.SaslConfigs;
        //   import org.apache.kafka.common.config.SslConfigs;
        // ---------------------------------------------------------------------

        try (KafkaProducer<String, String> producer = new KafkaProducer<>(props)) {
            IntStream.rangeClosed(1, 5).forEach(i -> {
                String key = "user-" + i;
                String value = "{\"id\":" + i + ",\"message\":\"Hello from Korvet client " + i + "\"}";
                ProducerRecord<String, String> record = new ProducerRecord<>(TOPIC, key, value);
                producer.send(record, (RecordMetadata metadata, Exception exception) -> {
                    if (exception != null) {
                        System.err.println("Send failed: " + exception.getMessage());
                        return;
                    }
                    System.out.printf("Sent key=%s to %s-%d@%d%n",
                            key, metadata.topic(), metadata.partition(), metadata.offset());
                });
            });
            producer.flush();
            System.out.println("Done. Sent 5 records to topic '" + TOPIC + "'.");
        }
    }
}
