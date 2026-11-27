# ============================================================================
# addons.tf — 平台组件自动安装
#
# terraform apply 一条命令 = CCE + Spark Operator + JupyterHub + Argo + Ingress
#
# 平台组件清单：
#   ingress-nginx      —— 独享型 ELB 的 Ingress 控制器
#   spark-operator     —— Spark 作业 Operator
#   argo-workflows     —— 工作流编排
#   jupyterhub         —— 交互式开发入口
#   spark-etl-platform —— 平台清单 Chart：../charts/spark-etl-platform（RBAC/作业模板/Ingress）
# ============================================================================

# （helm provider 版本约束统一声明在 main.tf 的 required_providers）

# ----------------------------------------------------------------------------
# 开关：如需"只建基础设施、暂不装平台组件"，apply 时 -var="enable_addons=false"
# ----------------------------------------------------------------------------
variable "enable_addons" {
  description = "是否随 apply 自动安装平台组件（Spark Operator/JupyterHub/Argo/Ingress）"
  type        = bool
  default     = true
}

variable "ingress_domain" {
  description = "Ingress 域名后缀；留空则自动使用 <ELB_EIP>.nip.io（无需注册域名即可访问）"
  type        = string
  default     = ""
}

# ----------------------------------------------------------------------------
# 从 CCE 集群提取访问凭据（EIP 公网 apiserver），供 helm provider 使用
# ----------------------------------------------------------------------------
locals {
  cce_certs = {
    for c in huaweicloud_cce_cluster.main.certificate_clusters : c.name => c
  }
  # 优先走公网端点（本机执行 terraform 时需公网可达）
  cce_server = try(
    local.cce_certs["externalCluster"].server,
    huaweicloud_cce_cluster.main.certificate_clusters[0].server
  )
  cce_ca = try(
    local.cce_certs["externalClusterTLSVerify"].certificate_authority_data,
    huaweicloud_cce_cluster.main.certificate_clusters[0].certificate_authority_data
  )
  cce_client_cert = huaweicloud_cce_cluster.main.certificate_users[0].client_certificate_data
  cce_client_key  = huaweicloud_cce_cluster.main.certificate_users[0].client_key_data

  # 域名策略：有自有域名用域名，没有就用 EIP.nip.io（免费泛解析，开箱即用）
  domain_suffix = var.ingress_domain != "" ? var.ingress_domain : "${huaweicloud_vpc_eip.ingress.address}.nip.io"
  jhub_host     = "jhub.${local.domain_suffix}"
  argo_host     = "argo.${local.domain_suffix}"
}

provider "helm" {
  kubernetes {
    host               = local.cce_server
    client_certificate = base64decode(local.cce_client_cert)
    client_key         = base64decode(local.cce_client_key)
    # CCE 公网端点证书对 EIP 域名校验不匹配 → 跳过服务端证书校验；
    # 注意 insecure=true 时不能同时提供 cluster_ca_certificate（helm 限制）
    insecure = true
  }
}

# ----------------------------------------------------------------------------
# ① ingress-nginx：挂在 Terraform 创建的独享型 ELB 之后
# ----------------------------------------------------------------------------
resource "helm_release" "ingress_nginx" {
  count            = var.enable_addons ? 1 : 0
  name             = "ingress-nginx"
  # Chart 已本地化（charts/vendor/），避免运行时依赖 github.io 网络
  chart            = "${path.module}/../charts/vendor/ingress-nginx-4.10.1.tgz"
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    controller = {
      # registry.k8s.io 会 302 到 Google 源（国内经 NAT 也不可达），
      # 改用 DaoCloud 国内镜像代理；digest 置空以按 tag 拉取
      image = {
        registry = "k8s.m.daocloud.io"
        digest   = ""
      }
      admissionWebhooks = {
        patch = {
          image = {
            registry = "k8s.m.daocloud.io"
            digest   = ""
          }
        }
      }
      service = {
        type = "LoadBalancer"
        annotations = {
          # 复用 Terraform 已创建的独享型 ELB（含 EIP）
          "kubernetes.io/elb.id"    = huaweicloud_elb_loadbalancer.ingress.id
          "kubernetes.io/elb.class" = "performance"
        }
      }
    }
  })]

  # 必须等节点池有可调度节点（节点已绑定 EIP，可经 SNAT 直接出网拉取镜像）
  depends_on = [huaweicloud_cce_node_pool.ondemand]
}

# ----------------------------------------------------------------------------
# ② Spark Operator
# ----------------------------------------------------------------------------
resource "helm_release" "spark_operator" {
  count            = var.enable_addons ? 1 : 0
  name             = "spark-operator"
  chart            = "${path.module}/../charts/vendor/spark-operator-1.4.6.tgz"
  namespace        = "spark-operator"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    sparkJobNamespace = "spark"
    webhook           = { enable = true }
  })]

  depends_on = [huaweicloud_cce_node_pool.ondemand]
}

# ----------------------------------------------------------------------------
# ③ Argo Workflows（提供 WorkflowTemplate CRD）
# ----------------------------------------------------------------------------
resource "helm_release" "argo_workflows" {
  count            = var.enable_addons ? 1 : 0
  name             = "argo-workflows"
  chart            = "${path.module}/../charts/vendor/argo-workflows-0.41.11.tgz"
  namespace        = "argo"
  create_namespace = true
  wait             = true
  timeout          = 900

  values = [yamlencode({
    server = {
      extraArgs = ["--auth-mode=server"]
    }
  })]

  depends_on = [huaweicloud_cce_node_pool.ondemand]
}

# ----------------------------------------------------------------------------
# ④ 平台清单 Chart：RBAC + Argo WorkflowTemplate + Ingress
#    （由 src/manifests/*.yaml 封装为 Chart；依赖 Argo 的 CRD）
# ----------------------------------------------------------------------------
resource "helm_release" "platform" {
  count     = var.enable_addons ? 1 : 0
  name      = "spark-etl-platform"
  chart     = "${path.module}/../charts/spark-etl-platform"
  namespace = "default"
  wait      = true
  timeout   = 600

  values = [yamlencode({
    region        = var.region
    swrOrg        = huaweicloud_swr_organization.main.name
    jhubHost      = local.jhub_host
    argoHost      = local.argo_host
    appCodeBucket = huaweicloud_obs_bucket.app_code.bucket
    # OBS 凭据：默认沿用 provider 的 AK/SK；生产建议改用独立最小权限凭据
    obsAccessKey = var.obs_access_key
    obsSecretKey = var.obs_secret_key
  })]

  depends_on = [helm_release.argo_workflows]
}

variable "obs_access_key" {
  description = "注入 Spark 作业访问 OBS 的 AK（建议创建独立最小权限凭据）"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_HW_ACCESS_KEY"
}

variable "obs_secret_key" {
  description = "注入 Spark 作业访问 OBS 的 SK"
  type        = string
  sensitive   = true
  default     = "REPLACE_WITH_HW_SECRET_KEY"
}

# ----------------------------------------------------------------------------
# ⑤ JupyterHub（登录密码来自 var，与 CSMS 一致）
# ----------------------------------------------------------------------------
resource "helm_release" "jupyterhub" {
  count            = var.enable_addons ? 1 : 0
  name             = "jupyterhub"
  chart            = "${path.module}/../charts/vendor/jupyterhub-3.3.8.tgz"
  namespace        = "jupyter"
  create_namespace = false # 命名空间由 platform Chart 创建
  wait             = true
  timeout          = 1200

  values = [yamlencode({
    hub = {
      config = {
        JupyterHub = { authenticator_class = "dummy" }
        DummyAuthenticator = { password = var.jhub_secret_password }
        Authenticator = { admin_users = ["sparkoneks"] }
      }
      # 集群无默认 StorageClass，显式用华为云云硬盘 csi-disk；
      # 华为云 EVS 最小规格 10Gi（chart 默认 1Gi 无法供给）
      db = {
        pvc = {
          storageClassName = "csi-disk"
          storage          = "10Gi"
        }
      }
    }
    proxy = {
      service = { type = "ClusterIP" } # 出口统一走 ingress-nginx + ELB
    }
    singleuser = {
      serviceAccountName = "jupyter-sa"
      memory             = { limit = "2G", guarantee = "1G" }
      # 用户卷同样显式指定 csi-disk 并满足 EVS 10Gi 最小规格
      storage = {
        dynamic  = { storageClass = "csi-disk" }
        capacity = "10Gi"
      }
    }
    # prePuller 的 pause 镜像与 userScheduler 的 kube-scheduler 镜像
    # 均来自 registry.k8s.io（302 到 Google 源，国内 NAT 也不可达），
    # 关闭两者：镜像改为用户 spawn 时按需拉取，调度用集群默认调度器
    prePuller = {
      hook       = { enabled = false }
      continuous = { enabled = false }
    }
    scheduling = {
      userScheduler = { enabled = false }
    }
  })]

  depends_on = [helm_release.platform, helm_release.ingress_nginx]
}

# ----------------------------------------------------------------------------
# 访问入口输出
# ----------------------------------------------------------------------------
output "jupyterhub_url" {
  value       = var.enable_addons ? "http://${local.jhub_host}  （用户: sparkoneks / 密码: var.jhub_secret_password）" : "addons 未启用"
  description = "JupyterHub 访问地址"
}

output "argo_url" {
  value       = var.enable_addons ? "http://${local.argo_host}" : "addons 未启用"
  description = "Argo Workflows 控制台地址"
}
