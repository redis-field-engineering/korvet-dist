# =============================================================================
# Spark Structured Streaming Consumer for Korvet
# =============================================================================
# Reads from Korvet using Kafka protocol with consumer group
# Writes to Delta Lake in S3
#
# Update S3 paths before deployment:
#   - checkpointLocation
#   - output path (start() call)
# =============================================================================

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, from_json, current_timestamp
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

# Initialize Spark session
spark = SparkSession.builder \
    .appName("KorvetToDelta") \
    .getOrCreate()

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
    .option("kafka.bootstrap.servers", "korvet.korvet.svc.cluster.local:9092") \
    .option("subscribe", "logs") \
    .option("kafka.group.id", "spark-delta-consumer") \
    .option("startingOffsets", "earliest") \
    .option("maxOffsetsPerTrigger", 100000) \
    .option("kafka.session.timeout.ms", "30000") \
    .option("kafka.request.timeout.ms", "60000") \
    .option("kafka.enable.auto.commit", "false") \
    .load()

# Parse Kafka messages
parsed_df = df.select(
    col("key").cast("string").alias("key"),
    from_json(col("value").cast("string"), log_schema).alias("data"),
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
).withColumn(
    "ingestion_time", current_timestamp()
)

# Write to Delta Lake in S3
# UPDATE THESE PATHS with terraform output
query = parsed_df.writeStream \
    .format("delta") \
    .outputMode("append") \
    .option("checkpointLocation", "s3a://korvet-poc-REGION-SUFFIX/spark/checkpoints/logs") \
    .option("mergeSchema", "true") \
    .partitionBy("topic") \
    .trigger(processingTime="30 seconds") \
    .start("s3a://korvet-poc-REGION-SUFFIX/spark/output/logs")

query.awaitTermination()
