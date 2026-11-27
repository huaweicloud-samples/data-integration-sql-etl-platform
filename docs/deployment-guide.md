# 部署指导书：基于 CCE 的 Spark SQL 声明式 ETL 平台

> 目标：在华为云一条命令端到端部署「Spark SQL 声明式 ETL」平台。
> 预计耗时：约 25~40 分钟（含 CCE 集群创建）。区域默认 `cn-north-4`（北京四）。

## A. 前置准备

1. 华为云账号已完成实名认证，账户余额充足（按需资源创建时会校验额度）。
2. 获取访问密钥：控制台 → 我的凭证 → 访问密钥 → 新增访问密钥（AK/SK）。
3. 本机安装 Terraform ≥ 1.5（国内网络建议配合华为云 provider 镜像源，见 `infra/.terraformrc-hwmirror`）。

```bash
export HW_ACCESS_KEY="<AK>"
export HW_SECRET_KEY="<SK>"
```

## B. 一键部署（Terraform）

```bash
cd infra
export TF_CLI_CONFIG_FILE=./.terraformrc-hwmirror # 可选：使用华为云镜像源加速 provider 下载
terraform init
terraform apply -auto-approve
```

一条 `apply` 将依序完成两层：

**基础设施层（18 个资源）**
VPC/双可用区子网/安全组、CCE 集群（v1.28）+ 按需/弹性节点池、OBS 代码桶与数据湖桶、DEW KMS 密钥 + CSMS 凭据、SWR 组织、独享型 ELB + EIP。

**平台组件层（5 个 helm_release，`addons.tf` 自动安装）**
```
CCE 节点池就绪
├─→ ingress-nginx（复用 ELB 作为统一入口）
├─→ Spark Operator
└─→ Argo Workflows
└─→ 平台清单 Chart（RBAC / WorkflowTemplate / Ingress）
└─→ JupyterHub（登录密码即 CSMS 托管凭据）
```

完成后终端输出：
- `jupyterhub_url` / `argo_url`（基于 `<ELB公网IP>.nip.io` 泛解析，浏览器直接打开）
- 集群 ID、OBS 桶名、ELB 公网 IP

> 如只需基础设施层：`terraform apply -var="enable_addons=false"`。
> 首次 apply 若因镜像拉取超时中断，重跑 `terraform apply` 会断点续装。

## C. 镜像加速（可选，推荐）

境外镜像仓库在国内拉取较慢时，将 Arc 运行时镜像同步至 SWR：

```bash
docker pull ghcr.io/tripl-ai/arc:arc_3.11.1_spark_3.1.2_scala_2.12_hadoop_3.2.0_1.0.0
docker tag ghcr.io/tripl-ai/arc:arc_3.11.1_spark_3.1.2_scala_2.12_hadoop_3.2.0_1.0.0 \
swr.cn-north-4.myhuaweicloud.com/<org>/arc:latest
docker push swr.cn-north-4.myhuaweicloud.com/<org>/arc:latest
```

## D. 数据接入（OBS）

Spark 作业统一通过 `src/adapter/obs_spark_adapter.py` 注入 OBS 端点配置：

- `spark.hadoop.fs.obs.impl=org.apache.hadoop.fs.obs.OBSFileSystem`
- `spark.hadoop.fs.obs.access.key / secret.key` 来自 CSMS（经 CCE 委托注入，不落盘）
- 数据路径统一使用 `obs://bucket/...` 协议

## E. 提交 ETL 作业

### 路径 A —— Argo / Spark Operator（推荐）
```bash
# kubeconfig：CCE 控制台一键下载，或按 terraform output 提示获取
export KUBECONFIG=./kubeconfig.yaml
argo submit src/manifests/nyctaxi-job-scheduler.yaml -n spark --watch
kubectl get sparkapplication -n spark # 期待 COMPLETED
```

### 路径 B —— MRS on CCE（托管 Spark 场景）
```bash
# 在 MRS 控制台创建「MRS on CCE」集群后提交 Arc notebook 作业
bash src/jobs/submit_arc_job_huawei.sh
```

## F. 即席查询（DLI）

在 DLI 建库表指向 OBS 数据湖上的 Parquet，执行即席 SQL：
```sql
SELECT * FROM default.contact_snapshot WHERE id = 12;
```

## G. 清理

```bash
cd infra && terraform destroy -auto-approve
```
> KMS 密钥销毁有 7 天冻结期，属正常机制。

## 验证清单

- [ ] `terraform apply` 输出 `Apply complete`，outputs 含 `jupyterhub_url` / `argo_url`
- [ ] CCE 集群 Ready，按需 + 弹性节点池均就绪
- [ ] `helm list -A`：5 个 release 全部 `deployed`
- [ ] 浏览器打开 `jupyterhub_url` 登录成功（密码在 CSMS）
- [ ] 提交一个 nyctaxi ETL 作业，`sparkapplication` 状态 `COMPLETED`，OBS 数据湖桶产出 Parquet
- [ ] DLI 能查询到产出表
- [ ] LTS 收到作业日志
