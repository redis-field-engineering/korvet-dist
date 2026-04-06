#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="korvet-poc"

echo "=== Setting up EBS CSI Driver ==="

# Get OIDC issuer
OIDC_ISSUER=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" \
  --query "cluster.identity.oidc.issuer" --output text | sed 's|https://||')

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create trust policy
cat > /tmp/ebs-csi-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_ISSUER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_ISSUER}:aud": "sts.amazonaws.com",
          "${OIDC_ISSUER}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

# Create IAM role
echo "Creating IAM role for EBS CSI driver..."
aws iam create-role \
  --role-name "AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}" \
  --assume-role-policy-document file:///tmp/ebs-csi-trust-policy.json \
  --region "$REGION" 2>/dev/null || echo "Role already exists"

aws iam attach-role-policy \
  --role-name "AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy 2>/dev/null || true

# Install EBS CSI addon
echo "Installing EBS CSI addon..."
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}" \
  --region "$REGION" 2>/dev/null || \
aws eks update-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --service-account-role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AmazonEKS_EBS_CSI_DriverRole_${CLUSTER_NAME}" \
  --region "$REGION" 2>/dev/null || true

echo "Waiting for EBS CSI driver to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=aws-ebs-csi-driver -n kube-system --timeout=120s 2>/dev/null || sleep 30
kubectl get pods -n kube-system | grep ebs

echo "EBS CSI driver setup complete"
