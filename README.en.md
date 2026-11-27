# data-integration-sql-etl-platform

[![License](https://img.shields.io/badge/License-MIT--No--Attribution-green.svg)](LICENSE)
[![Huawei Cloud](https://img.shields.io/badge/Huawei%20Cloud-Best%20Practice-blue.svg)](https://www.huaweicloud.com)
[![Terraform](https://img.shields.io/badge/terraform-validated-success.svg)](https://www.terraform.io)

Build a "SQL-centric" declarative ETL data platform on Huawei Cloud: developed with JupyterHub (Arc framework), orchestrated by Argo Workflows, executed by Spark Operator, stored in an OBS data lake, and queried ad hoc with DLI — the entire stack is deployed end-to-end by a single Terraform command.

## 1. Overview

This practice builds a declarative ETL data platform on Huawei Cloud: it is SQL-centric, developed with JupyterHub (Arc framework), orchestrated by Argo Workflows, executed by Spark Operator, stored in an OBS data lake, and queried ad hoc with DLI — the entire stack is deployed end-to-end by a single Terraform command.

## 2. Table of Contents

- [1. Overview](#1-overview)
- [2. Table of Contents](#2-table-of-contents)
- [3. Architecture Diagram](#3-architecture-diagram)
- [4. Highlights](#4-highlights)
- [5. Cloud Services Used](#5-cloud-services-used)
- [6. Prerequisites](#6-prerequisites)
- [7. Quick Start](#7-quick-start)
- [8. Step-by-Step Deployment](#8-step-by-step-deployment)
- [9. Usage / Verification](#9-usage--verification)
- [10. Cleanup](#10-cleanup)
- [11. Detailed Explanation](#11-detailed-explanation)
- [12. Dependencies](#12-dependencies)
- [13. FAQ / Troubleshooting](#13-faq--troubleshooting)
- [14. Contributing](#14-contributing)
- [15. License](#15-license)
- [16. Contact / Maintainers](#16-contact--maintainers)

Repository layout:

```
<repository root>/
├── docs/ # Huawei Cloud practice documents
│ ├── architecture.md # Architecture description (incl. architecture diagram)
│ ├── deployment-guide.md # Deployment guide
├── infra/ # Terraform IaC (one-command deployment of the full stack)
│ ├── main.tf # Infrastructure: CCE/OBS/DEW/SWR/ELB
│ ├── addons.tf # Platform components: ingress-nginx/Spark Operator/Argo/JupyterHub
│ └── variables.tf
├── charts/
│ └── spark-etl-platform/ # Platform manifest chart (RBAC/WorkflowTemplate/Ingress)
├── src/
│ ├── adapter/obs_spark_adapter.py # OBS endpoint configuration adapter
│ ├── manifests/ # K8s manifests (charted, kept for reference)
│ └── jobs/submit_arc_job_huawei.sh # MRS-path job submission script
└── README.md
```

## 3. Architecture Diagram

See [docs/architecture.md](docs/architecture.md).

## 4. Highlights

- **SQL-centric**: Data processing logic is declared in SQL, no Spark code required
- **Full-stack IaC**: One Terraform command deploys the stack end-to-end (infrastructure + platform components)
- **JupyterHub integration**: The Arc framework submits Argo Workflows directly
- **DLI ad hoc queries**: Run SQL queries directly against the OBS data lake

## 5. Cloud Services Used

| Capability | Huawei Cloud Service |
|------|-----------|
| Container platform | CCE Cloud Container Engine (on-demand + elastic node pool) |
| Managed Spark | MRS on CCE / CCE + Spark Operator |
| Object storage / data lake | OBS (Hadoop-OBS connector, `obs://` protocol) |
| Image repository | SWR |
| Credentials / secrets | DEW (CSMS + KMS) |
| Ad hoc queries | DLI |
| Ingress | ELB + ingress-nginx |
| Logs | LTS |
| IaC | Terraform + huaweicloud / helm provider |

## 6. Prerequisites

- A Huawei Cloud account with permissions to create CCE / OBS / DEW / SWR / ELB / DLI / LTS
- Local tools: Terraform >= 1.5, helm, kubectl, docker
- Credentials are provided via environment variables (do not write to files): `HW_ACCESS_KEY`, `HW_SECRET_KEY`

## 7. Quick Start

```bash
export HW_ACCESS_KEY=<your-AK>
export HW_SECRET_KEY=<your-SK>
cd infra
terraform init
terraform apply -auto-approve # infrastructure + all platform components, end-to-end
```

After apply completes (about 25-40 minutes), the outputs `jupyterhub_url` / `argo_url` are printed; open them directly in a browser (the free wildcard domain `<ELB_EIP>.nip.io` is used by default, no domain registration needed).

Optional — sync the Arc image to SWR (recommended when pulling the overseas image is slow):

```bash
docker pull ghcr.io/tripl-ai/arc:arc_3.11.1_spark_3.1.2_scala_2.12_hadoop_3.2.0_1.0.0
docker tag ... swr.cn-north-4.myhuaweicloud.com/sparketl/arc:latest
docker push swr.cn-north-4.myhuaweicloud.com/sparketl/arc:latest

# Submit a sample ETL job
bash src/jobs/submit_arc_job_huawei.sh
```

> To "create infrastructure only, without installing platform components yet": `terraform apply -var="enable_addons=false"`

## 8. Step-by-Step Deployment

1. Set the Huawei Cloud AK/SK environment variables.
2. Enter the `infra/` directory.
3. Run `terraform init` to initialize the providers.
4. Run `terraform apply -auto-approve` for end-to-end deployment (about 25-40 minutes).
5. Obtain `jupyterhub_url` / `argo_url` from the outputs.
6. Optional: sync the Arc image to SWR, then run the sample ETL job.

## 9. Usage / Verification

- ✅ `terraform validate` passed
- ✅ `terraform plan` (measured in cn-north-4): 23 to add (18 infrastructure + 5 platform components)
- ⏳ `terraform apply` end-to-end pending execution

After deployment, follow these steps to verify that the business functionality works before considering the delivery complete.

## 10. Cleanup

```bash
cd infra && terraform destroy
```

## 11. Detailed Explanation

- Architecture and components: see [docs/architecture.md](docs/architecture.md)
- Deployment steps: see [docs/deployment-guide.md](docs/deployment-guide.md)

## 12. Dependencies

- Huawei Cloud Terraform Provider (`huaweicloud`)
- Helm Provider (`hashicorp/helm`)
- Huawei Cloud native services: CCE / OBS / DEW / SWR / ELB / DLI / LTS

## 13. FAQ / Troubleshooting

Detailed FAQ: see [docs/deployment-guide.md](docs/deployment-guide.md).

## 14. Contributing

Issues and Pull Requests are welcome. Please follow the existing repository structure and code style.

## 15. License

This practice is released under the MIT No Attribution license. See [LICENSE](LICENSE).

## 16. Contact / Maintainers
| Item | Content |
|---|---|
| **Creator** | [dgc-git](https://github.com/dgc-git) |
| **Maintainer** | [dgc-git](https://github.com/dgc-git) |
| **Contact** | GitHub Issues / PR (see [Section 14](#14-contributing)) |
