#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REGION="${AWS_REGION:-us-west-2}"
OWNER="${OWNER:-$(whoami)}"

echo "=== Deploying EKS Pipeline ==="
echo "Region: $REGION"
echo "Owner: $OWNER"
echo ""

# Step 1: Terraform
echo ">>> Step 1: Deploying infrastructure with Terraform..."
cd "$ROOT_DIR/terraform"
terraform init
terraform apply -var="region=$REGION" -var="owner=$OWNER" -auto-approve

# Get outputs
S3_BUCKET=$(terraform output -raw s3_bucket_name)
KORVET_IAM_ROLE=$(terraform output -raw korvet_iam_role_arn)
SPARK_IAM_ROLE=$(terraform output -raw spark_iam_role_arn)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)

echo ""
echo ">>> Step 2: Configuring kubectl..."
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "$REGION"

# Step 3: Add EKS access for current user
echo ""
echo ">>> Step 3: Configuring EKS access..."
PRINCIPAL_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
aws eks create-access-entry --cluster-name "$EKS_CLUSTER" --principal-arn "$PRINCIPAL_ARN" --region "$REGION" 2>/dev/null || true
aws eks associate-access-policy --cluster-name "$EKS_CLUSTER" --principal-arn "$PRINCIPAL_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region "$REGION" 2>/dev/null || true

# Step 4: Setup EBS CSI driver
echo ""
echo ">>> Step 4: Setting up EBS CSI driver..."
"$SCRIPT_DIR/setup-ebs-csi.sh"

# Step 5: Create namespaces
echo ""
echo ">>> Step 5: Creating namespaces..."
kubectl create namespace redis 2>/dev/null || true
kubectl create namespace korvet 2>/dev/null || true
kubectl create namespace spark 2>/dev/null || true

# Step 6: Install Redis Enterprise Operator
echo ""
echo ">>> Step 6: Installing Redis Enterprise Operator..."
helm install redis-enterprise-operator \
  https://github.com/RedisLabs/redis-enterprise-helm/releases/download/redis-enterprise-operator-7.22.2-38/redis-enterprise-operator-7.22.2-38.tgz \
  -n redis 2>/dev/null || echo "Operator already installed"

kubectl wait --for=condition=available deployment/redis-enterprise-operator -n redis --timeout=300s

# Step 7: Deploy Redis Enterprise Cluster
echo ""
echo ">>> Step 7: Deploying Redis Enterprise Cluster..."
kubectl apply -f "$ROOT_DIR/k8s/redis-enterprise-cluster.yaml"
echo "Waiting for Redis Enterprise Cluster (this takes 5-10 minutes)..."
kubectl wait --for=condition=Running rec/rec -n redis --timeout=600s

# Step 8: Deploy Redis Database
echo ""
echo ">>> Step 8: Deploying Redis Database..."
kubectl apply -f "$ROOT_DIR/k8s/redis-enterprise-database.yaml"
sleep 30  # Wait for database to be ready

# Step 9: Copy Redis secret to korvet namespace
echo ""
echo ">>> Step 9: Copying Redis secret..."
kubectl get secret redb-korvet-db -n redis -o json | \
  jq 'del(.metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.namespace, .metadata.ownerReferences)' | \
  kubectl apply -n korvet -f -

# Step 10: Update Korvet manifests with actual values
echo ""
echo ">>> Step 10: Configuring Korvet..."
cd "$ROOT_DIR/k8s/korvet"
sed -i.bak "s|arn:aws:iam::ACCOUNT_ID:role/korvet-poc-s3-access|$KORVET_IAM_ROLE|g" serviceaccount.yaml
sed -i.bak "s|S3_BUCKET|$S3_BUCKET|g" configmap.yaml
rm -f *.bak

# Step 11: Deploy Korvet
echo ""
echo ">>> Step 11: Deploying Korvet..."
kubectl apply -f "$ROOT_DIR/k8s/korvet/"
kubectl wait --for=condition=available deployment/korvet -n korvet --timeout=120s

# Step 12: Create topic
echo ""
echo ">>> Step 12: Creating topic..."
kubectl run kafka-cli --image confluentinc/cp-kafka:7.5.0 --restart=Never -n korvet -- sleep 3600 2>/dev/null || true
sleep 10

kubectl exec kafka-cli -n korvet -- kafka-topics \
  --bootstrap-server korvet.korvet.svc.cluster.local:9092 \
  --create --topic logs --partitions 4 2>/dev/null || echo "Topic already exists"

# Configure tiered storage settings:
# - bucket.duration.ms=300000 (5 min) - how often buckets are sealed and archived
# - retention.ms=1800000 (30 min) - TTL for data in Redis (buckets expire after this + bucket duration)
# - remote.storage.enable=true - enable archival to S3
kubectl exec kafka-cli -n korvet -- kafka-configs \
  --bootstrap-server korvet.korvet.svc.cluster.local:9092 \
  --entity-type topics --entity-name logs \
  --alter --add-config 'bucket.duration.ms=300000,retention.ms=1800000,remote.storage.enable=true'

# Step 13: Deploy Logstash
echo ""
echo ">>> Step 13: Deploying Logstash..."
kubectl apply -f "$ROOT_DIR/k8s/logstash/"
kubectl wait --for=condition=available deployment/logstash -n korvet --timeout=120s

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "S3 Bucket: $S3_BUCKET"
echo "EKS Cluster: $EKS_CLUSTER"
echo ""
echo "Run ./scripts/verify.sh to check the pipeline"
