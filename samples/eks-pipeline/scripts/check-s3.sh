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
echo ">>> By Partition:"
for i in 0 1 2 3; do
  COUNT=$(aws s3 ls "s3://$S3_BUCKET/korvet/delta/korvet/stream/logs/$i/" --recursive 2>/dev/null | wc -l | tr -d ' ')
  echo "  logs/$i: $COUNT files"
done
