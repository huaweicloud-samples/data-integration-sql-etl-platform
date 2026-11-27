#!/bin/bash
# ============================================================================
# 一键提交 nyctaxi ETL 作业到华为云 CCE（前提：terraform apply 已完成）
#
# 关键配置（可直接复现）：
#   1. notebook/schema 通过预生成的 ConfigMap(nyctaxi-config.yaml) 挂载为本地文件，
#      Arc 用 file:///opt/arc/nyctaxi.ipynb 读取——不再依赖 GitHub raw（避免 429）。
#   2. 数据源走 S3A 协议访问 OBS（s3a://nyc-tlc/csv_backup），不再用 Arc 不支持的 obs://。
#   3. spark-rbac.yaml 已含 pods 的 patch/update，Arc 收尾打注解不再误标 Error。
#   4. OBS 凭据从环境变量注入 obs-creds secret（生产用 CSMS，见 deployment-guide）。
#
# 用法（在仓库根目录执行）：
#   export HW_REGION=cn-north-4
#   export CLUSTER_ID=<terraform output cce_cluster_id>
#   export SWR_ORG=<SWR 组织名>
#   export APP_CODE_BUCKET=spark-etl-app-code
#   export DATALAKE_BUCKET=spark-etl-datalake
#   export HW_ACCESS_KEY=<OBS AK> HW_SECRET_KEY=<OBS SK>   # 或集群内已有 obs-creds 时留空
#   export KUBECONFIG=./kubeconfig.yaml                    # 已有 kubeconfig 时直接指定
#   bash src/jobs/submit_arc_job_huawei.sh
# ============================================================================
set -e

export HW_REGION=${HW_REGION:-cn-north-4}
CLUSTER_ID=${CLUSTER_ID:-""}
SWR_ORG=${SWR_ORG:?请设置 SWR 组织名（如 sparketl）}
APP_CODE_BUCKET=${APP_CODE_BUCKET:?请设置 OBS 代码桶}
DATALAKE_BUCKET=${DATALAKE_BUCKET:?请设置 OBS 数据湖桶}

# 1. kubeconfig：已有则直接用，否则用 hw CLI 获取
if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
  echo "[1/5] 使用已有 kubeconfig: $KUBECONFIG"
elif command -v hw >/dev/null 2>&1 && [ -n "$CLUSTER_ID" ]; then
  echo "[1/5] 通过 hw cce get-credentials 获取 kubeconfig"
  hw cce get-credentials --cluster-id "$CLUSTER_ID" --kubeconfig ./kubeconfig.yaml
  export KUBECONFIG=./kubeconfig.yaml
else
  echo "ERROR: 请设置 KUBECONFIG 或 (CLUSTER_ID 且安装 hw CLI)" >&2
  exit 1
fi

# 2. OBS 凭据 secret（环境变量注入；为空则依赖集群已有 obs-creds）
if [ -n "$HW_ACCESS_KEY" ] && [ -n "$HW_SECRET_KEY" ]; then
  echo "[2/5] 注入 obs-creds secret"
  kubectl create secret generic obs-creds -n spark \
    --from-literal=ACCESS_KEY="$HW_ACCESS_KEY" \
    --from-literal=SECRET_KEY="$HW_SECRET_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "[2/5] 未提供 HW_ACCESS_KEY/SECRET，假设 obs-creds 已存在（否则作业会报 NoAwsCredentials）"
fi

# 3. RBAC / WorkflowTemplate / Ingress
echo "[3/5] 应用 RBAC 与平台组件"
kubectl apply -f src/manifests/spark-rbac.yaml
kubectl apply -f src/manifests/arcjob-rbac.yaml
kubectl apply -f src/manifests/spark-template.yaml
kubectl apply -f src/manifests/ingress.yaml

# 4. nyctaxi-config ConfigMap（notebook+schema，挂载到 /opt/arc）
#    如需重新生成：python3 src/jobs/build_nyctaxi_configmap.py \
#      --notebook src/notebooks/nyctaxi.ipynb \
#      --schema   src/notebooks/green_tripdata0.json \
#      --out      src/manifests/nyctaxi-config.yaml
echo "[4/5] 应用 nyctaxi-config ConfigMap"
kubectl apply -f src/manifests/nyctaxi-config.yaml

# 5. 提交作业（作业逻辑来自 ConfigMap，无需外网拉取；数据源 s3a://，结果写回 OBS）
echo "[5/5] 提交 nyctaxi 作业 (Argo Workflow)"
kubectl create -f src/manifests/nyctaxi-job-scheduler.yaml

echo ""
echo "作业已提交。ETL 结果将写入 s3a://${DATALAKE_BUCKET}/nyctaxi-output/"
echo "查看状态: kubectl -n spark get workflow"
echo "查看日志: kubectl -n spark logs -l workflows.argoproj.io/workflow=nyctaxi-job-<id> -c main -f"
