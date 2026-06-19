#!/usr/bin/env python3
"""Reads a small sample from the Delta latency analytics table."""

from pyspark.sql import SparkSession


spark = (
    SparkSession.builder.appName("KorvetReadDeltaAnalytics")
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

spark.read.format("delta").load("s3a://korvet-analytics/delta/event-latencies").select(
    "request_id",
    "service",
    "status_code",
    "event_gen_timestamp",
    "logstash_send_timestamp",
    "logstash_payload_send_timestamp",
    "korvet_receive_timestamp",
    "korvet_send_timestamp",
    "spark_read_timestamp",
    "event_gen_to_spark_read_latency_ms",
).show(20, truncate=False)
