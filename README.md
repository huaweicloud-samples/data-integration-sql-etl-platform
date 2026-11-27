# data-integration-sql-etl-platform · 基于 CCE 的 Spark SQL 声明式 ETL 平台（华为云实践）

[![License](https://img.shields.io/badge/License-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)
在华为云上构建「以 SQL 为中心」的声明式 ETL 数据平台：JupyterHub（Arc 框架）开发
Argo Workflows 编排、Spark Operator 执行、OBS 数据湖存储、DLI 即席查询——
全栈由 Terraform 一条命令端到端部署。

## 1. 简介 / Overview

### 简介


本实践在华为云上构建声明式 ETL 数据平台：以 SQL 为中心，用 JupyterHub（Arc 框架）开发、Argo Workflows 编排、Spark Operator 执行、OBS 数据湖存储、DLI 即席查询——全栈由 Terraform 一条命令端到端部署。

---

## 2. 目录


- [1. 简介 / Overview](#1-简介--overview)
- [2. 目录](#2-目录)
- [3. 架构图](#3-架构图)
- [4. 方案亮点](#4-方案亮点)
- [5. 涉及云服务](#5-涉及云服务)
- [6. 前置条件](#6-前置条件)
- [7. 快速开始](#7-快速开始)
- [8. 分步部署](#8-分步部署)
- [9. 使用方法 / 验证](#9-使用方法--验证)
- [10. 清理资源](#10-清理资源)
- [11. 详细说明](#11-详细说明)
- [12. 依赖](#12-依赖)
- [13. FAQ / 故障排除](#13-faq--故障排除)
- [14. 贡献指南](#14-贡献指南)
- [15. 许可证](#15-许可证)
- [16. 联系方式 / 维护者](#16-联系方式--维护者)


```
<仓库根>/
├── docs/ # 华为云实践文档
│ ├── architecture.md # 架构说明（含架构图）
│ ├── deployment-guide.md # 部署指导书
├── infra/ # Terraform IaC（一条命令部署全栈）
│ ├── main.tf # 基础设施：CCE/OBS/DEW/SWR/ELB
│ ├── addons.tf # 平台组件：ingress-nginx/Spark Operator/Argo/JupyterHub
│ └── variables.tf
├── charts/
│ └── spark-etl-platform/ # 平台清单 Chart（RBAC/WorkflowTemplate/Ingress）
├── src/
│ ├── adapter/obs_spark_adapter.py # OBS 端点配置适配器
│ ├── manifests/ # K8s 清单（已 Chart 化，留档参考）
│ └── jobs/submit_arc_job_huawei.sh # MRS 路径作业提交脚本
└── README.md
```

---

## 3. 架构图

详见 [docs/architecture.md](docs/architecture.md)。

---

## 4. 方案亮点

- **SQL 中心**：以 SQL 声明数据处理逻辑，无需编写 Spark 代码
- **全栈 IaC**：Terraform 一条命令端到端部署（基础设施 + 平台组件）
- **JupyterHub 集成**：Arc 框架直接提交 Argo Workflows
- **DLI 即席查询**：直接对 OBS 数据湖做 SQL 查询

---

## 5. 涉及云服务

| 能力 | 华为云服务 |
|------|-----------|
| 容器平台 | CCE 云容器引擎（按需 + 弹性节点池） |
| 托管 Spark | MRS on CCE / CCE + Spark Operator |
| 对象存储 / 数据湖 | OBS（Hadoop-OBS connector，`obs://` 协议） |
| 镜像仓库 | SWR |
| 凭据 / 密钥 | DEW（CSMS + KMS） |
| 即席查询 | DLI |
| 入口 | ELB + ingress-nginx |
| 日志 | LTS |
| IaC | Terraform + huaweicloud / helm provider |

---

## 6. 前置条件

- 华为云账号，具备 CCE / OBS / DEW / SWR / ELB / DLI / LTS 创建权限
- 本地工具：Terraform ≥ 1.5、helm、kubectl、docker
- 凭据通过环境变量提供（**禁止写入文件**）：`HW_ACCESS_KEY`、`HW_SECRET_KEY`

---

## 7. 快速开始

### 快速开始（一条命令）


```bash
export HW_ACCESS_KEY=<你的AK>
export HW_SECRET_KEY=<你的SK>
cd infra
terraform init
terraform apply -auto-approve # 基础设施 + 全部平台组件，端到端
```

apply 完成后（约 25-40 分钟），输出 `jupyterhub_url` / `argo_url`，浏览器直接访问
（默认使用 `<ELB_EIP>.nip.io` 免费泛域名，无需注册域名）。

可选操作——把 Arc 镜像同步到 SWR（境外镜像拉取慢时建议做）：

```bash
docker pull ghcr.io/tripl-ai/arc:arc_3.11.1_spark_3.1.2_scala_2.12_hadoop_3.2.0_1.0.0
docker tag ... swr.cn-north-4.myhuaweicloud.com/sparketl/arc:latest
docker push swr.cn-north-4.myhuaweicloud.com/sparketl/arc:latest

# 提交示例 ETL 作业
bash src/jobs/submit_arc_job_huawei.sh
```

> 如需"只建基础设施、暂不装平台组件"：`terraform apply -var="enable_addons=false"`

---

## 8. 分步部署

1. 设置华为云 AK/SK 环境变量。
2. 进入 `infra/` 目录。
3. 执行 `terraform init` 初始化 provider。
4. 执行 `terraform apply -auto-approve` 端到端部署（约 25-40 分钟）。
5. 通过 outputs 获取 `jupyterhub_url` / `argo_url`。
6. 可选：将 Arc 镜像同步到 SWR 后执行示例 ETL 作业。

---

## 9. 使用方法 / 验证

### 使用方法与验证


- ✅ `terraform validate` 通过
- ✅ `terraform plan`（cn-north-4 实测）：23 to add（18 基础设施 + 5 平台组件）
- ⏳ `terraform apply` 端到端待执行

---

## 10. 清理资源

```bash
cd infra && terraform destroy
```

---

## 11. 详细说明

- 架构与组件：见 [docs/architecture.md](docs/architecture.md)
- 部署步骤：见 [docs/deployment-guide.md](docs/deployment-guide.md)

---

## 12. 依赖

- 华为云 Terraform Provider (`huaweicloud`)
- Helm Provider (`hashicorp/helm`)
- 华为云原生服务：CCE / OBS / DEW / SWR / ELB / DLI / LTS

---

## 13. FAQ / 故障排除

### FAQ

- 详细 FAQ 见 [docs/deployment-guide.md](docs/deployment-guide.md)。

---

## 14. 贡献指南

欢迎提交 Issue 与 PR。请遵循仓库内现有目录结构与代码风格。

---

## 15. 许可证

本实践以 MIT No Attribution 许可证发布。详见 [LICENSE](LICENSE)。

---

## 16. 联系方式 / 维护者
| 项 | 内容 |
|---|---|
| **创建者** | [dgc-git](https://github.com/dgc-git) |
| **维护者** | [dgc-git](https://github.com/dgc-git) |
| **联系方式** | GitHub Issues / PR（见[第 14 节](#14-贡献指南)） |
