#!/bin/bash
set -e

# --- CONFIGURATION ---
# نستخدم القيم من الـ Environment Variables لو موجودة، وإلا نستخدم القيم الافتراضية
CLUSTER_NAME="${CLUSTER_NAME:-my-eks-cluster-v2}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# جلب رقم الحساب ديناميكياً بدلاً من كتابته يدوياً
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Configuration ==="
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo "Kubeconfig: $KUBECONFIG"

echo "=== Installing OS dependencies ==="
# كشف نوع نظام التشغيل لحل مشكلة apt-get not found
if command -v dnf &> /dev/null; then
    sudo dnf update -y
    sudo dnf install -y curl unzip jq tar
elif command -v yum &> /dev/null; then
    sudo yum update -y
    sudo yum install -y curl unzip jq tar
elif command -v apt-get &> /dev/null; then
    sudo apt-get update -y
    sudo apt-get install -y curl unzip jq
else
    echo "Unknown package manager. Please install curl, unzip, and jq manually."
fi

# --- AWS CLI v2 ---
if ! command -v aws &> /dev/null; then
    echo "Installing AWS CLI v2..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -o awscliv2.zip
    sudo ./aws/install --update
    rm -rf aws awscliv2.zip
else
    echo "AWS CLI is already installed."
fi

# --- eksctl ---
if ! command -v eksctl &> /dev/null; then
    echo "Installing eksctl..."
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
else
    echo "eksctl is already installed."
fi

# --- kubectl ---
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/
else
    echo "kubectl is already installed."
fi

# --- Helm ---
if ! command -v helm &> /dev/null; then
    echo "Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm is already installed."
fi

# --- Update kubeconfig ---
echo "=== Updating kubeconfig for EKS cluster ==="
# نستخدم الأمر بدون تحديد مسار، لأنه سيعتمد على متغير البيئة KUBECONFIG القادم من Jenkins
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# --- Verify access ---
echo "=== Verifying kubectl access ==="
kubectl get nodes || { echo "kubectl cannot access the cluster"; exit 1; }

# --- IAM OIDC ---
echo "=== Associating IAM OIDC Provider ==="
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve || true

# --- EBS CSI policy ---
echo "=== Configuring EBS CSI IAM Policy ==="
POLICY_NAME="AmazonEBSCSIPolicy-$CLUSTER_NAME"
POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

# إنشاء ملف السياسة
cat <<JSON > ebs-csi-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AttachVolume",
        "ec2:DetachVolume",
        "ec2:CreateSnapshot",
        "ec2:DeleteSnapshot",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeTags",
        "ec2:DescribeVolumes",
        "ec2:DescribeVolumesModifications",
        "ec2:ModifyVolume"
      ],
      "Resource": "*"
    }
  ]
JSON

# التحقق مما إذا كانت السياسة موجودة، إذا لم تكن موجودة قم بإنشائها
if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo "Policy $POLICY_NAME already exists."
else
    echo "Creating IAM Policy: $POLICY_NAME"
    aws iam create-policy --policy-name $POLICY_NAME --policy-document file://ebs-csi-policy.json
fi

# --- IAM Service Account ---
echo "=== Creating IAM Service Account for EBS CSI ==="
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --attach-policy-arn $POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts || true

# --- Install EBS CSI Driver ---
echo "=== Installing EBS CSI Driver using Helm ==="
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --create-namespace \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

echo "=== DONE! EBS CSI driver installed/updated successfully. ==="