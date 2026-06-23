#!/usr/bin/env python3
"""
Consumes Logstash events from Korvet and writes latency analytics as Delta tables
to an S3-compatible bucket.
"""

import os

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, expr, from_json, lit, when
from pyspark.sql.types import IntegerType, StringType, StructField, StructType


KAFKA_BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS", "korvet:9092")
SOURCE_TOPIC = os.getenv("SOURCE_TOPIC", "logs")
CHECKPOINT_PATH = os.getenv(
    "CHECKPOINT_PATH",
    "s3a://korvet-analytics/checkpoints/event-latencies",
)
OUTPUT_PATH = os.getenv(
    "OUTPUT_PATH",
    "s3a://korvet-analytics/delta/event-latencies",
)
MAX_OFFSETS_PER_TRIGGER = os.getenv("MAX_OFFSETS_PER_TRIGGER", "50000")


event_schema = StructType(
    [
        StructField("event_gen_timestamp", StringType(), True),
        StructField("logstash_send_timestamp", StringType(), True),
        StructField("level", StringType(), True),
        StructField("service", StringType(), True),
        StructField("host", StringType(), True),
        StructField("request_id", StringType(), True),
        StructField("path", StringType(), True),
        StructField("response_time_ms", IntegerType(), True),
        StructField("status_code", IntegerType(), True),
        StructField("bytes", IntegerType(), True),
        StructField("client_ip", StringType(), True),
    ]
)


def main():
    spark = (
        SparkSession.builder.appName("KorvetLogstashS3DeltaAnalytics")
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.hadoop.fs.s3a.endpoint", "http://minio:9000")
        .config("spark.hadoop.fs.s3a.access.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.secret.key", "minioadmin")
        .config("spark.hadoop.fs.s3a.path.style.access", "true")
        .config("spark.hadoop.fs.s3a.connection.ssl.enabled", "false")
        .config(
            "spark.hadoop.fs.s3a.aws.credentials.provider",
            "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider",
        )
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    kafka_df = (
        spark.readStream.format("kafka")
        .option("kafka.bootstrap.servers", KAFKA_BOOTSTRAP_SERVERS)
        .option("subscribe", SOURCE_TOPIC)
        .option("kafka.group.id", "spark-delta-analytics")
        .option("startingOffsets", "earliest")
        .option("maxOffsetsPerTrigger", MAX_OFFSETS_PER_TRIGGER)
        .option("failOnDataLoss", "false")
        .option("includeHeaders", "true")
        .load()
    )

    parsed_df = (
        kafka_df.select(
            col("key").cast("string").alias("key"),
            from_json(col("value").cast("string"), event_schema).alias("data"),
            col("topic"),
            col("partition"),
            col("offset"),
            col("timestamp").alias("kafka_record_timestamp"),
            col("headers"),
        )
        .select("key", "data.*", "topic", "partition", "offset", "kafka_record_timestamp", "headers")
        .withColumnRenamed("logstash_send_timestamp", "logstash_payload_send_timestamp")
        .withColumn("event_gen_timestamp", col("event_gen_timestamp").cast("timestamp"))
        .withColumn(
            "logstash_payload_send_timestamp",
            col("logstash_payload_send_timestamp").cast("timestamp"),
        )
        .withColumn("logstash_send_timestamp", col("kafka_record_timestamp"))
        .withColumn(
            "korvet_receive_timestamp",
            expr(
                "timestamp_millis(CAST(get(transform("
                "filter(headers, h -> h.key = 'korvet.log.append.timestamp.ms'), "
                "h -> CAST(h.value AS STRING)), 0) AS BIGINT))"
            ),
        )
        .drop("headers")
        .withColumn("korvet_send_timestamp", lit(None).cast("timestamp"))
        .withColumn("spark_read_timestamp", expr("current_timestamp()"))
        .withColumn(
            "event_gen_to_logstash_send_latency_ms",
            expr("unix_millis(logstash_send_timestamp) - unix_millis(event_gen_timestamp)"),
        )
        .withColumn(
            "logstash_send_to_korvet_receive_latency_ms",
            expr("unix_millis(korvet_receive_timestamp) - unix_millis(logstash_send_timestamp)"),
        )
        .withColumn(
            "korvet_receive_to_spark_read_latency_ms",
            expr("unix_millis(spark_read_timestamp) - unix_millis(korvet_receive_timestamp)"),
        )
        .withColumn(
            "event_gen_to_spark_read_latency_ms",
            expr("unix_millis(spark_read_timestamp) - unix_millis(event_gen_timestamp)"),
        )
        .withColumn(
            "status_class",
            when(col("status_code") >= 500, lit("5xx"))
            .when(col("status_code") >= 400, lit("4xx"))
            .when(col("status_code") >= 300, lit("3xx"))
            .when(col("status_code") >= 200, lit("2xx"))
            .otherwise(lit("other")),
        )
    )

    query = (
        parsed_df.writeStream.format("delta")
        .outputMode("append")
        .option("checkpointLocation", CHECKPOINT_PATH)
        .option("mergeSchema", "true")
        .partitionBy("service", "status_class")
        .trigger(processingTime="15 seconds")
        .start(OUTPUT_PATH)
    )

    print("Writing Delta latency analytics")
    print(f"  source topic: {SOURCE_TOPIC}")
    print(f"  output path:  {OUTPUT_PATH}")
    print(f"  checkpoint:   {CHECKPOINT_PATH}")
    query.awaitTermination()


if __name__ == "__main__":
    main()
