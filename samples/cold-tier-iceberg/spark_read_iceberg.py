#!/usr/bin/env python3
"""Reads Korvet's Iceberg cold tier through the Redis-backed catalog.

Korvet's OffloadService writes sealed segments to Iceberg tables whose metadata
lives in Redis (the RedisCatalog) and whose Parquet data files live in S3/MinIO.
This script points Spark at that same catalog so you can query the cold tier
with ordinary SQL.

Key configuration contract (must match the Korvet deployment):

  * catalog-impl     com.redis.korvet.storage.tiered.iceberg.catalog.RedisCatalog
  * uri              the Redis instance Korvet uses for catalog metadata
  * warehouse        the same value as korvet.storage.remote.path (s3://...)
  * key-prefix       "{korvet.namespace}:storage:tiered:iceberg"
                     -> default namespace "korvet" => "korvet:storage:tiered:iceberg"
  * file-io-impl     S3FileIO, plus the same s3.* settings Korvet uses

The RedisCatalog class is shipped in the korvet-storage-tiered-iceberg jar (and
its runtime dependencies). The Makefile extracts those jars from the
redisfield/korvet image into ./catalog-jars and mounts them on the Spark
classpath via --jars.
"""

import glob
import os

from pyspark.sql import SparkSession


REDIS_URI = os.getenv("REDIS_URI", "redis://redis:6379")
WAREHOUSE = os.getenv("WAREHOUSE", "s3://korvet-cold/warehouse")
# Default Korvet namespace is "korvet"; the catalog key-prefix is derived from it.
KEY_PREFIX = os.getenv("KORVET_CATALOG_KEY_PREFIX", "korvet:storage:tiered:iceberg")
# Korvet maps each Kafka topic to one Iceberg table in a namespace named after
# korvet.namespace (default "korvet"). Topic "events" -> table korvet.events.
NAMESPACE = os.getenv("ICEBERG_NAMESPACE", "korvet")
TABLE = os.getenv("ICEBERG_TABLE", "events")

S3_ENDPOINT = os.getenv("S3_ENDPOINT", "http://minio:9000")
S3_ACCESS_KEY = os.getenv("S3_ACCESS_KEY", "minioadmin")
S3_SECRET_KEY = os.getenv("S3_SECRET_KEY", "minioadmin")
S3_REGION = os.getenv("S3_REGION", "us-east-1")


def main():
    catalog = "korvet"
    prefix = f"spark.sql.catalog.{catalog}"
    spark = (
        SparkSession.builder.appName("KorvetReadColdTierIceberg")
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions")
        .config(prefix, "org.apache.iceberg.spark.SparkCatalog")
        .config(f"{prefix}.catalog-impl", "com.redis.korvet.storage.tiered.iceberg.catalog.RedisCatalog")
        .config(f"{prefix}.uri", REDIS_URI)
        .config(f"{prefix}.warehouse", WAREHOUSE)
        .config(f"{prefix}.key-prefix", KEY_PREFIX)
        .config(f"{prefix}.io-impl", "org.apache.iceberg.aws.s3.S3FileIO")
        .config(f"{prefix}.s3.endpoint", S3_ENDPOINT)
        .config(f"{prefix}.s3.access-key-id", S3_ACCESS_KEY)
        .config(f"{prefix}.s3.secret-access-key", S3_SECRET_KEY)
        .config(f"{prefix}.s3.path-style-access", "true")
        .config(f"{prefix}.client.region", S3_REGION)
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    print(f"Namespaces in catalog '{catalog}':")
    spark.sql(f"SHOW NAMESPACES IN {catalog}").show(truncate=False)

    print(f"Tables in {catalog}.{NAMESPACE}:")
    spark.sql(f"SHOW TABLES IN {catalog}.{NAMESPACE}").show(truncate=False)

    fqtn = f"{catalog}.{NAMESPACE}.{TABLE}"
    print(f"Schema of {fqtn}:")
    spark.sql(f"DESCRIBE TABLE {fqtn}").show(truncate=False)

    print(f"Sample rows from {fqtn} (ordered by message_ts):")
    spark.sql(
        f"""
        SELECT stream_key, segment_id, message_id, message_ts, fields
        FROM {fqtn}
        ORDER BY message_ts
        LIMIT 20
        """
    ).show(truncate=False)

    print(f"Row count per partition stream in {fqtn}:")
    spark.sql(
        f"SELECT stream_key, count(*) AS rows FROM {fqtn} GROUP BY stream_key ORDER BY stream_key"
    ).show(truncate=False)

    spark.stop()


if __name__ == "__main__":
    # Fail early with a clear message if the catalog jars were not mounted.
    if not glob.glob("/opt/korvet-jars/*.jar"):
        raise SystemExit(
            "No catalog jars found under /opt/korvet-jars. "
            "Run `make catalog-jars` first to extract them from the Korvet image."
        )
    main()
