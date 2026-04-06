#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REGION="${AWS_REGION:-us-west-2}"
OWNER="${OWNER:-$(whoami)}"

echo "=== Destroying EKS Pipeline ==="
echo ""

read -p "Are you sure you want to destroy all resources? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted"
  exit 1
fi

echo ""
echo ">>> Deleting Kubernetes resources..."
kubectl delete -f "$ROOT_DIR/k8s/logstash/" 2>/dev/null || true
kubectl delete -f "$ROOT_DIR/k8s/korvet/" 2>/dev/null || true
kubectl delete -f "$ROOT_DIR/k8s/redis-enterprise-database.yaml" 2>/dev/null || true
kubectl delete -f "$ROOT_DIR/k8s/redis-enterprise-cluster.yaml" 2>/dev/null || true
kubectl delete pod kafka-cli -n korvet 2>/dev/null || true

echo ""
echo ">>> Uninstalling Redis Enterprise Operator..."
helm uninstall redis-enterprise-operator -n redis 2>/dev/null || true

echo ""
echo ">>> Deleting namespaces..."
kubectl delete namespace korvet 2>/dev/null || true
kubectl delete namespace spark 2>/dev/null || true
# Don't delete redis namespace - let Terraform handle it

echo ""
echo ">>> Deleting EBS CSI driver IAM role..."
aws iam detach-role-policy \
  --role-name "AmazonEKS_EBS_CSI_DriverRole_korvet-poc" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true
aws iam delete-role --role-name "AmazonEKS_EBS_CSI_DriverRole_korvet-poc" 2>/dev/null || true

echo ""
echo ">>> Destroying infrastructure with Terraform..."
cd "$ROOT_DIR/terraform"
terraform destroy -var="region=$REGION" -var="owner=$OWNER" -auto-approve

echo ""
echo "=== Destroy Complete ==="
