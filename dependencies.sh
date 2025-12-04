#!/bin/bash

# --- CONFIGURATION ---
CLUSTER_NAME="my-eks-cluster"
ACCOUNT_ID="148712431636"
REGION="us-east-1" 

echo "=== Checking for Helm installation ==="
if ! command -v helm &> /dev/null
then
    echo "Helm not found. Installing Helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm is already installed."
fi

echo "=== Associating IAM OIDC Provider ==="
# Added --region here
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve

echo "=== Creating EBS CSI IAM policy ==="
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
}
JSON

POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/AmazonEBSCSIPolicy"

# Check if policy already exists
if aws iam get-policy --policy-arn $POLICY_ARN >/dev/null 2>&1; then
    echo "Policy AmazonEBSCSIPolicy already exists. Skipping creation."
else
    aws iam create-policy \
      --policy-name AmazonEBSCSIPolicy \
      --policy-document file://ebs-csi-policy.json
fi

echo "=== Creating IAM Service Account for EBS CSI ==="
# Added --region here
eksctl create iamserviceaccount \
  --cluster $CLUSTER_NAME \
  --region $REGION \
  --namespace kube-system \
  --name ebs-csi-controller-sa \
  --attach-policy-arn $POLICY_ARN \
  --approve \
  --override-existing-serviceaccounts

echo "=== Installing EBS CSI Driver using Helm ==="
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo update

helm upgrade --install aws-ebs-csi-driver aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --create-namespace \
  --set controller.serviceAccount.create=false \
  --set controller.serviceAccount.name=ebs-csi-controller-sa

echo "=== DONE! EBS CSI driver installed successfully. ==="
