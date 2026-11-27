#!/bin/bash

# SPDX-FileCopyrightText: Copyright 2021 本开源样例贡献者.
# SPDX-License-Identifier: MIT-0

# Define params
export HW_REGION=cn-north-4
export EKSCLUSTERNAME=eks-cluster
export EMRCLUSTERNAME=emr-on-$EKSCLUSTERNAME
export ROLENAME=${EMRCLUSTERNAME}-execution-role

#submit test job
export EMRCLUSTERID=$(hw emr list-virtual-clusters --query "virtualClusters[?name == '${EMRCLUSTERNAME}' && state == 'RUNNING'].id" --output text)
export ACCOUNTID=$(hw iam get-caller-identity --query Account --output text)
export ROLEARN=hw:iam::$ACCOUNTID:role/$ROLENAME
export OUTPUTS3BUCKET=${EMRCLUSTERNAME}-${ACCOUNTID}
export POLICYARN=hw:iam::$ACCOUNTID:policy/${ROLENAME}-policy

# install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# clean up resources
hw emr delete-virtual-cluster --id $EMRCLUSTERID
eksctl delete cluster --name=$EKSCLUSTERNAME
hw iam detach-role-policy --role-name $ROLENAME --policy-urn $POLICYARN
hw iam delete-role --role-name $ROLENAME
hw iam delete-policy --policy-urn $POLICYARN
obsutil rm obs://$OUTPUTS3BUCKET -r -f

