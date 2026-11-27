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

# install kubectl
curl -L "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl" \
    -o "/tmp/kubectl" 
chmod +x /tmp/kubectl
sudo mv /tmp/kubectl /usr/local/bin

# sumbit job

hw emr start-job-run --virtual-cluster-id $EMRCLUSTERID \
    --name arc-job --execution-role-arn $ROLEARN --release-label emr-6.2.0-latest \
    --job-driver '{"sparkSubmitJobDriver": {"entryPoint": "https://repo1.maven.org/maven2/ai/tripl/arc_2.12/3.6.2/arc_2.12-3.6.2.jar", "entryPointArguments":["--etl.config.uri=https://raw.githubusercontent.com/huaweicloud/data-integration-sql-etl-platform/main/emr-on-eks/green_taxi_load.ipynb"], "sparkSubmitParameters": "--packages com.typesafe:config:1.4.0 --class ai.tripl.arc.ARC --conf spark.executor.instances=10 --conf spark.executor.memory=4G --conf spark.driver.memory=2G --conf spark.executor.cores=2 --conf spark.kubernetes.driverEnv.ETL_CONF_ENV=production --conf spark.kubernetes.driverEnv.OUTPUT=obs://'$OUTPUTS3BUCKET'/output/ --conf spark.kubernetes.driverEnv.SCHEMA=https://raw.githubusercontent.com/huaweicloud/data-integration-sql-etl-platform/main/emr-on-eks/green_taxi_schema.json"}}' \
    --configuration-overrides '{"monitoringConfiguration": {"logConfiguration": {"logGroupName": "/cce/'$EKSCLUSTERNAME'/jobs", "logStreamNamePrefix": "arc-job"}}}'

echo "Job submitted"
echo "请在华为云 CCE 控制台查看作业状态（集群 ID: "${EMRCLUSTERID}"）"

echo "输出桶：obs://"${OUTPUTS3BUCKET}"（可在华为云 OBS 控制台查看）"
