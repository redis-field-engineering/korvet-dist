#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== S3 Bucket Status ==="
echo ""

cd "$ROOT_DIR/terraform"
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)

if [ -z "$S3_BUCKET" ]; then
  echo "Error: Could not get S3 bucket name from Terraform output"
  exit 1
fi

echo "Bucket: $S3_BUCKET"
echo ""

echo ">>> Contents:"
aws s3 ls "s3://$S3_BUCKET/" --recursive --human-readable --summarize

echo ""
echo ">>> Iceberg table (remote tier):"
# The remote tier is a single Apache Iceberg table under s3://$S3_BUCKET/korvet:
# a metadata/ directory plus Parquet data files (segment-*.parquet).
DATA_FILES=$(aws s3 ls "s3://$S3_BUCKET/korvet/" --recursive 2>/dev/null | grep -c '\.parquet$')
META_FILES=$(aws s3 ls "s3://$S3_BUCKET/korvet/metadata/" --recursive 2>/dev/null | wc -l | tr -d ' ')
echo "  Parquet data files: $DATA_FILES"
echo "  Metadata files:     $META_FILES"
