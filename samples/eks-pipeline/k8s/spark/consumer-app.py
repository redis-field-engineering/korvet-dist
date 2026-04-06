#!/usr/bin/env python3
"""
Spark Structured Streaming Consumer for Korvet

Reads from Korvet using Kafka protocol with consumer group.
Each executor reads different partitions (round-robin via consumer group).
Prints message counts per batch to demonstrate consumption.
"""

import os
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, count, window, current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

# Get config from environment
BOOTSTRAP_SERVERS = os.getenv("BOOTSTRAP_SERVERS", "korvet.korvet.svc.cluster.local:9092")
TOPIC = os.getenv("TOPIC", "logs")
GROUP_ID = os.getenv("GROUP_ID", "spark-consumer-group")
CHECKPOINT_LOCATION = os.getenv("CHECKPOINT_LOCATION", "/tmp/spark-checkpoint")

print(f"Starting Spark Consumer")
print(f"  Bootstrap servers: {BOOTSTRAP_SERVERS}")
print(f"  Topic: {TOPIC}")
print(f"  Consumer group: {GROUP_ID}")
print(f"  Checkpoint: {CHECKPOINT_LOCATION}")

# Initialize Spark session
spark = SparkSession.builder \
    .appName("KorvetConsumer") \
    .getOrCreate()

spark.sparkContext.setLogLevel("WARN")

# Schema for log events (matches Logstash generator output)
log_schema = StructType([
    StructField("timestamp", StringType()),
    StructField("level", StringType()),
    StructField("service", StringType()),
    StructField("host", StringType()),
    StructField("request_id", StringType()),
    StructField("path", StringType()),
    StructField("response_time_ms", IntegerType()),
    StructField("status_code", IntegerType()),
    StructField("bytes", IntegerType()),
    StructField("client_ip", StringType()),
])

# Read from Korvet using Kafka protocol with consumer group
df = spark.readStream \
    .format("kafka") \
    .option("kafka.bootstrap.servers", BOOTSTRAP_SERVERS) \
    .option("subscribe", TOPIC) \
    .option("kafka.group.id", GROUP_ID) \
    .option("startingOffsets", "latest") \
    .option("kafka.session.timeout.ms", "30000") \
    .option("kafka.request.timeout.ms", "60000") \
    .option("failOnDataLoss", "false") \
    .load()

# Parse Kafka messages and extract fields
parsed_df = df.select(
    col("partition"),
    col("offset"),
    from_json(col("value").cast("string"), log_schema).alias("data")
).select(
    "partition",
    "offset", 
    "data.*"
)

# Aggregate counts per batch for reporting
def process_batch(batch_df, batch_id):
    """Process each micro-batch and print stats"""
    count = batch_df.count()
    if count > 0:
        # Get partition distribution
        partition_counts = batch_df.groupBy("partition").count().collect()
        partition_str = ", ".join([f"p{row['partition']}={row['count']}" for row in partition_counts])
        
        # Get service distribution (sample)
        service_counts = batch_df.groupBy("service").count().orderBy(col("count").desc()).limit(3).collect()
        service_str = ", ".join([f"{row['service']}={row['count']}" for row in service_counts])
        
        print(f"Batch {batch_id}: {count} messages | Partitions: [{partition_str}] | Top services: [{service_str}]")

# Start streaming query with foreachBatch for custom processing
query = parsed_df.writeStream \
    .foreachBatch(process_batch) \
    .option("checkpointLocation", CHECKPOINT_LOCATION) \
    .trigger(processingTime="10 seconds") \
    .start()

print("Streaming query started. Waiting for data...")
query.awaitTermination()
