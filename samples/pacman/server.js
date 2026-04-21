const express = require('express');
const cors = require('cors');
const { Kafka } = require('kafkajs');
const path = require('path');

const app = express();
const PORT = 3000;

// Kafka/Korvet configuration
const KAFKA_BROKER = process.env.KAFKA_BROKER || 'localhost:9092';
const kafka = new Kafka({
  clientId: 'pacman-api',
  brokers: [KAFKA_BROKER],
  retry: {
    retries: 5,
    initialRetryTime: 300,
  }
});

const producer = kafka.producer();
const admin = kafka.admin();
const topics = ['USER_GAME', 'USER_LOSSES'];

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// Initialize Kafka producer
let producerReady = false;

async function ensureTopicsExist() {
  await admin.connect();

  try {
    const existingTopics = new Set(await admin.listTopics());
    const missingTopics = topics.filter((topic) => !existingTopics.has(topic));

    if (missingTopics.length === 0) {
      return;
    }

    await admin.createTopics({
      waitForLeaders: true,
      topics: missingTopics.map((topic) => ({
        topic,
        numPartitions: 1,
      })),
    });
  } finally {
    await admin.disconnect();
  }
}

async function initProducer() {
  try {
    await ensureTopicsExist();
    await producer.connect();
    producerReady = true;
    console.log('✅ Connected to Korvet (Kafka producer ready)');
  } catch (error) {
    console.error('❌ Failed to connect to Korvet:', error.message);
    console.error('   Make sure Korvet is running: docker-compose up -d');
    // Retry connection
    setTimeout(initProducer, 5000);
  }
}

initProducer();

// API endpoint to produce game events
app.post('/api/events', async (req, res) => {
  if (!producerReady) {
    return res.status(503).json({
      error: 'Kafka producer not ready. Please wait...'
    });
  }

  try {
    const { topic, event } = req.body;

    if (!topic || !event) {
      return res.status(400).json({
        error: 'Missing topic or event in request body'
      });
    }

    // Produce to Korvet
    await producer.send({
      topic: topic,
      messages: [
        {
          key: event.user || 'anonymous',
          value: JSON.stringify(event),
        },
      ],
    });

    console.log(`📤 Produced to ${topic}:`, event);

    res.json({
      success: true,
      topic: topic,
      message: 'Event produced successfully'
    });

  } catch (error) {
    console.error('❌ Error producing event:', error);
    res.status(500).json({
      error: 'Failed to produce event',
      details: error.message
    });
  }
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    korvet: producerReady ? 'connected' : 'disconnected',
    timestamp: new Date().toISOString()
  });
});

// Serve the game
app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  console.log('Shutting down gracefully...');
  await admin.disconnect().catch(() => {});
  await producer.disconnect();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('\nShutting down gracefully...');
  await admin.disconnect().catch(() => {});
  await producer.disconnect();
  process.exit(0);
});

app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════╗
║  🎮 Streaming Pac-Man with Korvet                         ║
╚═══════════════════════════════════════════════════════════╝

  API Server:  http://localhost:${PORT}
  Game:        http://localhost:${PORT}
  Korvet:      ${KAFKA_BROKER}

  Ready to stream game events! 🚀
  `);
});
