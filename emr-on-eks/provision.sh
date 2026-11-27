#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 本开源样例贡献者.
# SPDX-License-Identifier: MIT-0

# Define params
export HW_REGION=cn-north-4
export EKSCLUSTERNAME=eks-cluster
export EMRCLUSTERNAME=emr-on-$EKSCLUSTERNAME
export ROLENAME=${EMRCLUSTERNAME}-execution-role

# Using 容器集群服务 Fargate mode, uncomment to use 容器集群服务 弹性云服务器 mode
EKSCTL_PARAM="--fargate"
# 容器集群服务CTL_PARAM="--nodes 6 --node-type t3.xlarge"

# install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# install kubectl
curl -L "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o "/tmp/kubectl" 
chmod +x /tmp/kubectl
sudo mv /tmp/kubectl /usr/local/bin

# Provision eks cluster called “eks-fargate” backed by fargate
eksctl create cluster --name $EKSCLUSTERNAME --with-oidc --zones ${HW_REGION}a,${HW_REGION}b $EKSCTL_PARAM
hw cce update-kubeconfig --name $EKSCLUSTERNAME

# Create kubernetes namespace 'emr' for EMR
kubectl create namespace emr

# Create fargate profile 'fp-emr' for namespace 'emr'
eksctl create fargateprofile --cluster $EKSCLUSTERNAME --name fp-emr --namespace emr

# Wait for cluster to finish provisioning, enable all logging
# Enable cluster access for EMR in the 'emr' kubernetes namespace by running:
eksctl create iamidentitymapping --cluster $EKSCLUSTERNAME --namespace "emr" --service-name "emr-containers"
eksctl utils update-cluster-logging --cluster $EKSCLUSTERNAME --enable-types all --approve

# create S3 bucket for output
export ACCOUNTID=$(hw iam get-caller-identity --query Account --output text)
export OUTPUTS3BUCKET=${EMRCLUSTERNAME}-${ACCOUNTID}
obsutil mb obs://$OUTPUTS3BUCKET

# Create a job execution role
cat > /tmp/job-execution-policy.json <<EOL
{
    "Version": "2012-10-17",
    "Statement": [ 
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": ["obs://${OUTPUTS3BUCKET}","obs://${OUTPUTS3BUCKET}/*", "obs://nyc-tlc","obs://nyc-tlc/*"]
        }, 
        {
            "Effect": "Allow",
            "Action": [ "logs:PutLogEvents", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:CreateLogGroup" ],
            "Resource": [ "obs://logs/*" ]
        }
    ]
}

EOL

cat > /tmp/trust-policy.json <<EOL
{
  "Version": "2012-10-17",
  "Statement": [ {
      "Effect": "Allow",
      "Principal": { "Service": "cce.myhuaweicloud.com" },
      "Action": "sts:AssumeRole"
    } ]
}

EOL

ACCOUNTID=$(hw iam get-caller-identity --query Account --output text)
hw iam create-policy --policy-name $ROLENAME-policy --policy-document file:///tmp/job-execution-policy.json
hw iam create-role --role-name $ROLENAME --assume-role-policy-document file:///tmp/trust-policy.json
hw iam attach-role-policy --role-name $ROLENAME --policy-urn hw:iam::$ACCOUNTID:policy/$ROLENAME-policy
hw emr update-role-trust-policy --cluster-name $EKSCLUSTERNAME --namespace emr --role-name $ROLENAME

# Create emr virtual cluster
hw emr create-virtual-cluster --name $EMRCLUSTERNAME \
    --container-provider '{
        "id": "'$EKSCLUSTERNAME'",
        "type": "CCE",
        "info": { "cceInfo": { "namespace": "emr" } }
    }'

echo "Finished, proceed to submitting a job"