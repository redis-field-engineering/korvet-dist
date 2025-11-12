#!/usr/bin/env python3
"""
Spark Structured Streaming application that reads from Korvet using Kafka API.

This demonstrates Korvet's Kafka protocol compatibility with Apache Spark Streaming.
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, window, count, avg
from pyspark.sql.types import StructType, StructField, StringType, DoubleType, LongType

# Define schema for the JSON events
event_schema = StructType([
    StructField("event_id", StringType(), True),
    StructField("user_id", StringType(), True),
    StructField("event_type", StringType(), True),
    StructField("product_id", StringType(), True),
    StructField("price", DoubleType(), True),
    StructField("timestamp", LongType(), True)
])

def main():
    # Create Spark session with Kafka package
    spark = SparkSession.builder \
        .appName("KorvetSparkStreamingDemo") \
        .config("spark.jars.packages", "org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0") \
        .getOrCreate()
    
    spark.sparkContext.setLogLevel("WARN")
    
    print("=" * 80)
    print("Korvet + Spark Streaming Demo")
    print("=" * 80)
    print("Reading events from Korvet using Kafka API...")
    print()
    
    # Read from Korvet using Kafka API
    kafka_df = spark.readStream \
        .format("kafka") \
        .option("kafka.bootstrap.servers", "korvet:9092") \
        .option("subscribe", "events") \
        .option("startingOffsets", "earliest") \
        .option("failOnDataLoss", "false") \
        .load()
    
    print("Connected to Korvet successfully!")
    print()
    
    # Parse the JSON value
    events_df = kafka_df.select(
        col("key").cast("string").alias("key"),
        from_json(col("value").cast("string"), event_schema).alias("data"),
        col("topic"),
        col("partition"),
        col("offset"),
        col("timestamp").alias("kafka_timestamp")
    ).select(
        "key",
        "data.*",
        "topic",
        "partition",
        "offset",
        "kafka_timestamp"
    )
    
    # Display raw events
    print("Starting streaming query: Raw Events")
    query1 = events_df.writeStream \
        .outputMode("append") \
        .format("console") \
        .option("truncate", "false") \
        .queryName("raw_events") \
        .start()
    
    # Aggregate by event type (windowed)
    aggregated_df = events_df \
        .withWatermark("kafka_timestamp", "10 seconds") \
        .groupBy(
            window(col("kafka_timestamp"), "30 seconds"),
            col("event_type")
        ) \
        .agg(
            count("*").alias("event_count"),
            avg("price").alias("avg_price")
        )
    
    print("Starting streaming query: Aggregated Events")
    query2 = aggregated_df.writeStream \
        .outputMode("update") \
        .format("console") \
        .option("truncate", "false") \
        .queryName("aggregated_events") \
        .start()
    
    # Write to Parquet files (simulating data lake)
    print("Starting streaming query: Write to Parquet")
    query3 = events_df.writeStream \
        .outputMode("append") \
        .format("parquet") \
        .option("path", "/opt/spark-data/events") \
        .option("checkpointLocation", "/opt/spark-data/checkpoints/events") \
        .queryName("parquet_writer") \
        .start()
    
    print()
    print("=" * 80)
    print("All streaming queries started successfully!")
    print("=" * 80)
    print()
    print("Queries running:")
    print("  1. raw_events        - Display all events to console")
    print("  2. aggregated_events - Windowed aggregations by event type")
    print("  3. parquet_writer    - Write events to Parquet files")
    print()
    print("Spark UI: http://localhost:4040")
    print("Press Ctrl+C to stop...")
    print()
    
    # Wait for all queries to finish
    query1.awaitTermination()

if __name__ == "__main__":
    main()

