import java.time.Duration;
import java.util.Collections;
import java.util.Properties;

import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;

/**
 * Standard Kafka consumer pointed at Korvet's broker.
 *
 * Korvet supports consumer groups and offset commit just like Kafka. This
 * example joins a group, subscribes to a topic, polls in a loop, and commits
 * offsets manually with commitSync() after processing each batch.
 *
 * By default it connects to a Korvet broker on PLAINTEXT at localhost:9092
 * with no auth, which works out of the box against ../../kafka-cli.
 */
public final class Consumer {

    private static final String BOOTSTRAP_SERVERS = "localhost:9092";
    private static final String TOPIC = "client-demo";
    private static final String GROUP_ID = "client-demo-group";

    private Consumer() {
    }

    public static void main(String[] args) {
        Properties props = new Properties();
        props.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, BOOTSTRAP_SERVERS);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, GROUP_ID);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        // Start from the beginning when the group has no committed offset.
        props.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        // Manual commit: disable auto-commit and call commitSync() ourselves.
        props.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);

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

        try (KafkaConsumer<String, String> consumer = new KafkaConsumer<>(props)) {
            consumer.subscribe(Collections.singletonList(TOPIC));
            System.out.println("Subscribed to '" + TOPIC + "' as group '" + GROUP_ID + "'. Ctrl-C to stop.");
            while (true) {
                ConsumerRecords<String, String> records = consumer.poll(Duration.ofMillis(1000));
                for (ConsumerRecord<String, String> record : records) {
                    System.out.printf("Received key=%s value=%s (%s-%d@%d)%n",
                            record.key(), record.value(),
                            record.topic(), record.partition(), record.offset());
                }
                if (!records.isEmpty()) {
                    // Commit offsets only after the batch has been processed.
                    consumer.commitSync();
                }
            }
        }
    }
}
