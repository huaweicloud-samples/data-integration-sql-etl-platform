# 架构说明：基于 CCE 的 Spark SQL 声明式 ETL 平台

> 本实践在华为云上构建一套「以 SQL 为中心」的声明式 ETL 数据平台：数据工程师在 JupyterHub 中以 Spark SQL 编写 ETL 逻辑（Arc 声明式框架），由 Argo Workflows 编排、Spark Operator 调度执行，数据落 OBS 数据湖，DLI 提供即席查询。
> 区域默认 `cn-north-4`（北京四）。

## 一、整体架构

```
┌─────────────────────────────────────────────────┐
│ 华为云 VPC │
│ │
数据工程人员 │ ┌────────────── CCE 云容器引擎集群 ──────────┐ │
(浏览器 / kubectl) │ │ namespace: jupyter │ spark │ argo │ │
│ │ │ │ │
├──► JupyterHub │ │ • JupyterHub —— 网页版 ETL 开发环境 │ │
│ (Arc 框架) │ │ • Argo Workflows —— 作业编排（DAG） │ │
│ │ │ • Spark Operator —— Spark 作业调度引擎 │ │
├──► Argo UI ───►│ │ • ingress-nginx + ELB —— 统一入口 │ │
│ │ │ │ │
│ 提交 Spark │ │ ┌── 节点池 ────────────────────────┐ │ │
└──► 作业 ───────►│ │ │ 按需池（常驻服务） │ │ │
│ │ │ 弹性池 0~30 节点（作业自动扩缩） │ │ │
│ │ └──────────────────────────────────┘ │ │
│ └──────────────────────────────────────────────┘ │
│ │ │ │
│ ▼ ▼ │
│ ┌──────────────┐ ┌──────────────────┐ │
│ │ OBS 对象存储 │ │ DEW 数据加密工场 │ │
│ │ • 代码桶 │ │ • CSMS 凭据托管 │ │
│ │ • 数据湖桶 │ │ • KMS 加密 │ │
│ └──────────────┘ └──────────────────┘ │
│ │ │ │
│ ▼ ▼ │
│ ┌──────────────┐ ┌──────────────────┐ │
│ │ DLI 数据湖探索 │ │ LTS 云日志服务 │ │
│ │ （即席 SQL） │ │ （日志采集分析） │ │
│ └──────────────┘ └──────────────────┘ │
└─────────────────────────────────────────────────┘

镜像来源：SWR 容器镜像仓库（Arc/Spark 运行时镜像统一托管于此）
```

## 二、服务组成与职责

| 华为云服务 | 职责 |
|-----------|------|
| CCE 云容器引擎 | Kubernetes 集群底座，承载全部平台组件与 Spark 作业 |
| CCE 节点池（按需） | 运行 JupyterHub、Argo、Operator 等常驻服务 |
| CCE 节点池（弹性） | 0~30 节点自动扩缩，Spark Executor 按作业负载弹性伸缩 |
| OBS 对象存储 | 数据湖桶（ETL 输入/输出）+ 代码桶（PySpark 脚本与作业定义），`obs://` 协议经 Hadoop-OBS connector 接入 Spark |
| DEW（CSMS + KMS） | JupyterHub 登录凭据托管（不落明文）、OBS 服务端加密 |
| ELB + EIP | 独享型负载均衡对外暴露 JupyterHub / Argo UI |
| SWR | 容器镜像仓库，托管 Arc/Spark 运行时镜像 |
| DLI | 数据湖即席 SQL 查询，直接分析 OBS 上的 Parquet |
| LTS | 集群与作业日志采集 |
| IAM 委托 | CCE 集群经云服务委托访问 OBS/DEW/SWR/LTS，工作负载凭据经 CSMS 注入 |

## 三、两条作业提交路径

**路径 A —— Argo / Spark Operator（推荐，默认）**
JupyterHub 编写 Arc notebook → Argo 按 WorkflowTemplate 编排 DAG → Spark Operator 在 CCE 上拉起 Driver/Executor Pod → 读写 OBS 数据湖。

**路径 B —— MRS on CCE（托管 Spark 场景）**
将 Arc notebook 作为作业提交到运行在 CCE 上的 MRS Spark 集群，由 MRS 托管 Driver 生命周期；输出写 OBS。适合希望免运维 Spark 运行时的场景。

## 四、关键设计要点

1. **声明式 ETL 内核**：Arc 框架 + Spark SQL，业务逻辑以 SQL/notebook 表达，工程师无需编写 Spark 应用代码。
2. **K8s 原生弹性**：弹性节点池 + 动态资源分配（DRA），作业高峰自动扩容、空闲缩回 0。
3. **编排能力**：Argo Workflows 提供作业依赖（DAG）、定时调度与失败重试。
4. **安全基线**：凭据全程经 CSMS 托管注入，OBS 桶启用 KMS 加密，入口经 ELB 安全组收敛。
5. **一键交付**：全部基础设施与平台组件由 Terraform（huaweicloud + helm provider）一条 `terraform apply` 端到端拉起。
