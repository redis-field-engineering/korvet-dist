const { Kafka } = require('kafkajs');

// Kafka/Korvet configuration
const KAFKA_BROKER = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'pacman-consumer',
  brokers: [KAFKA_BROKER],
  retry: {
    retries: 5,
    initialRetryTime: 300,
  }
});

const consumer = kafka.consumer({ 
  groupId: 'pacman-event-viewer',
  sessionTimeout: 30000,
  heartbeatInterval: 3000,
});

const topics = ['USER_GAME', 'USER_LOSSES'];

async function run() {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  🎮 Pac-Man Event Consumer (Korvet)                       ║
╚═══════════════════════════════════════════════════════════╝

Connecting to Korvet at ${KAFKA_BROKER}...
  `);

  try {
    // Connect to Korvet
    await consumer.connect();
    console.log('✅ Connected to Korvet');

    // Subscribe to topics
    for (const topic of topics) {
      await consumer.subscribe({ topic, fromBeginning: true });
      console.log(`📡 Subscribed to topic: ${topic}`);
    }

    console.log(`
╔═══════════════════════════════════════════════════════════╗
║  Listening for events... (Press Ctrl+C to stop)           ║
╚═══════════════════════════════════════════════════════════╝
    `);

    // Consume messages
    await consumer.run({
      eachMessage: async ({ topic, partition, message }) => {
        const key = message.key ? message.key.toString() : 'null';
        const value = message.value.toString();
        
        let emoji = '📦';
        if (topic === 'USER_GAME') {
          emoji = '🎮';
        } else if (topic === 'USER_LOSSES') {
          emoji = '💀';
        }

        // Parse and pretty-print the event
        try {
          const event = JSON.parse(value);
          console.log(`${emoji} [${topic}] ${key}:`, JSON.stringify(event, null, 2));
        } catch (e) {
          console.log(`${emoji} [${topic}] ${key}: ${value}`);
        }
      },
    });

  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error('\nMake sure:');
    console.error('  1. Korvet is running: docker-compose up -d');
    console.error('  2. Wait 10 seconds for Korvet to start');
    console.error('  3. Check logs: docker-compose logs korvet');
    process.exit(1);
  }
}

// Graceful shutdown
const shutdown = async () => {
  console.log('\n\nShutting down consumer...');
  try {
    await consumer.disconnect();
    console.log('✅ Disconnected from Korvet');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
};

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// Run the consumer
run().catch(console.error);

