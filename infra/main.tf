# ============================================================================
# 基于 CCE 的 Spark SQL 声明式 ETL 平台
# 服务：CCE（K8s）+ OBS + DEW + SWR + ELB
# Provider: huaweicloud/huaweicloud ~> 1.70
# ============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.70"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
  }
}

provider "huaweicloud" {
  region = var.region
  # AK/SK 从环境变量读取，不硬编码
  # export HW_ACCESS_KEY / HW_SECRET_KEY
}

# 变量声明统一见 variables.tf

# ============================================================================
# L1 网络：VPC / 子网 / 安全组
# ============================================================================
resource "huaweicloud_vpc" "main" {
  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr
}

resource "huaweicloud_vpc_subnet" "az1" {
  name       = "${var.project_name}-subnet-az1"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.1.0/24"
  gateway_ip = "10.0.1.1"
  availability_zone = "${var.region}a"
}

resource "huaweicloud_vpc_subnet" "az2" {
  name       = "${var.project_name}-subnet-az2"
  vpc_id     = huaweicloud_vpc.main.id
  cidr       = "10.0.2.0/24"
  gateway_ip = "10.0.2.1"
  availability_zone = "${var.region}b"
}

resource "huaweicloud_networking_secgroup" "main" {
  name        = "${var.project_name}-sg"
  description = "Security group for ${var.project_name}"
}

resource "huaweicloud_networking_secgroup_rule" "allow_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main.id
}

resource "huaweicloud_networking_secgroup_rule" "allow_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main.id
}

# 临时：放通 kubelet 10250 以便 kubectl logs/exec 排查 JupyterHub spawn 问题
# 注意：kubelet 本身有证书认证，开放端口仅用于调试，取证完成后建议移除
resource "huaweicloud_networking_secgroup_rule" "allow_kubelet_debug" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = huaweicloud_networking_secgroup.main.id
}

# ============================================================================
# L1 IAM：CCE 集群与节点权限（Agency 委托 + 系统策略）
# 通过服务委托与项目角色实现集群级权限
# ============================================================================
# CCE 服务级授权委托。
# 缺少此委托时创建集群会报 CCE_CM.0101 "can't find assumeToDomainName"。
resource "huaweicloud_identity_agency" "cce_admin_trust" {
  name                  = "cce_admin_trust"
  description           = "Cloud service agency for CCE (auto-created by Terraform)"
  delegated_domain_name = "op_svc_cce"
  duration              = "FOREVER"
  all_resources_roles   = ["Tenant Administrator"]
}

resource "huaweicloud_identity_agency" "cce" {
  name               = "${var.project_name}-cce-agency"
  description        = "Agency for CCE to access OBS/DEW/SWR/LTS"
  duration           = "FOREVER"
  # 委托给 CCE 云服务（provider 无 identity_domain/project 数据源，
  # 服务委托用 delegated_service_name；项目名在华为云默认等于区域名）
  delegated_service_name = "op_svc_cce"

  project_role {
    project = var.region
    roles = [
      "OBS OperateAccess",
      "KMS Administrator",
      "SWR Admin",
      "LTS FullAccess",
    ]
  }
}

# ============================================================================
# L2 存储与加密：OBS + KMS
#   代码桶 app_code + 数据湖桶 datalake
# ============================================================================
resource "huaweicloud_kms_key" "main" {
  key_alias    = "${var.project_name}-key"
  pending_days = 7
  # KMS 托管加密
}

resource "huaweicloud_obs_bucket" "app_code" {
  bucket        = "${var.project_name}-app-code"
  acl           = "private"
  force_destroy = true
  versioning    = true
  encryption    = true
  kms_key_id    = huaweicloud_kms_key.main.id

  tags = {
    project = var.project_name
    source  = "spark-etl-platform"
  }
}

resource "huaweicloud_obs_bucket" "datalake" {
  bucket        = "${var.project_name}-datalake"
  acl           = "private"
  force_destroy = true
  versioning    = true
  encryption    = true
  kms_key_id    = huaweicloud_kms_key.main.id

  tags = {
    project = var.project_name
  }
}

# ============================================================================
# L4 凭据：DEW CSMS（JupyterHub 登录）
# 凭据由 CSMS 原生托管，运行时以环境变量/挂载方式注入
# ============================================================================
resource "huaweicloud_csms_secret" "jhub" {
  name        = "${var.project_name}-jhub-login"
  description = "JupyterHub login for ${var.project_name}"
  secret_type = "COMMON"
  # 明文凭据经 DEW 托管，运行时以环境变量/挂载方式注入 JupyterHub
  secret_text = jsonencode({
    username = "sparkoneks"
    password = var.jhub_secret_password
  })
  kms_key_id = huaweicloud_kms_key.main.id
}

# ============================================================================
# L1 容器：CCE 集群 + 节点池
#   按需节点池 + 弹性竞价节点池
# ============================================================================
resource "huaweicloud_cce_cluster" "main" {
  name                   = "${var.project_name}-cce"
  cluster_type           = "VirtualMachine" # CCE Standard 集群（API 取值）
  flavor_id              = "cce.s1.small"
  vpc_id                 = huaweicloud_vpc.main.id
  subnet_id              = huaweicloud_vpc_subnet.az1.id
  security_group_id      = huaweicloud_networking_secgroup.main.id
  # API 访问：公网+私网
  eip                    = huaweicloud_vpc_eip.cluster.address
  cluster_version        = "v1.28"
  container_network_type = "vpc-router" # 即控制台"VPC 网络"模式（API 取值）
  # 集群创建依赖 cce_admin_trust 服务委托已就位
  depends_on = [huaweicloud_identity_agency.cce_admin_trust]
}

resource "huaweicloud_vpc_eip" "cluster" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "${var.project_name}-cluster-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

# 按需节点池
resource "huaweicloud_cce_node_pool" "ondemand" {
  cluster_id         = huaweicloud_cce_cluster.main.id
  name               = "etl-ondemand"
  os                 = "EulerOS 2.9"
  # s6 通用型；8U16G 单节点可承载全部平台组件
  flavor_id          = "s6.2xlarge.2"
  initial_node_count = 1
  min_node_count     = 1
  max_node_count     = 5
  availability_zone  = "${var.region}a"
  password           = var.node_password
  # 子网继承 CCE 集群配置（provider 不支持 subnets/security_groups 参数）

  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }

  # 节点标签供 Spark/DRA 调度识别
  labels = {
    app          = "spark"
    lifecycle    = "OnDemand"
    "spark-node" = "true"
  }
}

# 弹性竞价节点池
resource "huaweicloud_cce_node_pool" "spot" {
  cluster_id         = huaweicloud_cce_cluster.main.id
  name               = "etl-spot"
  os                 = "EulerOS 2.9"
  # 初始 0 台，突发 Spark 负载时再扩容
  flavor_id          = "s6.xlarge.2"
  initial_node_count = 0
  min_node_count     = 0
  max_node_count     = 5
  availability_zone  = "${var.region}b"
  password           = var.node_password
  # 子网继承 CCE 集群配置

  root_volume {
    size       = 40
    volumetype = "SAS"
  }
  data_volumes {
    size       = 100
    volumetype = "SAS"
  }

  # CCE 节点池不直接暴露竞价参数，
  # 竞价能力建议通过「CCE 节点池 + ECS 竞价实例」在控制台/BSS 侧配置，
  # 或使用弹性伸缩池承接突发 Spark 负载
  labels = {
    app         = "spark"
    lifecycle   = "Spot"
    "spot-node" = "true"
  }
}

# ============================================================================
# L5 镜像仓库：SWR
# ============================================================================
resource "huaweicloud_swr_organization" "main" {
  # SWR 组织不支持 description 参数
  name = replace(var.project_name, "-", "")
}

# ============================================================================
# L5 入口：ELB + EIP（ingress-nginx 将挂在 ELB 之后）
# ============================================================================
resource "huaweicloud_vpc_eip" "ingress" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "${var.project_name}-ingress-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_elb_loadbalancer" "ingress" {
  name              = "${var.project_name}-elb"
  vpc_id            = huaweicloud_vpc.main.id
  ipv4_subnet_id    = huaweicloud_vpc_subnet.az1.ipv4_subnet_id
  availability_zone = ["${var.region}a"]
  # 绑定上方创建的 EIP（独享型 ELB 用 ipv4_eip_id 关联已有 EIP）
  ipv4_eip_id       = huaweicloud_vpc_eip.ingress.id

  # 规格由服务端按默认最小规格分配；忽略回写差异，避免误更新为空（ELB.8959）
  lifecycle {
    ignore_changes = [l4_flavor_id, l7_flavor_id]
  }
}

# ============================================================================
# L1 公网出口：NAT 网关 + EIP  （为 CCE 工作节点提供拉取镜像所需的公网出口）
# 背景：CCE 工作节点位于私有子网；docker.io 经 CCE 内网镜像加速可拉取，
# 但 quay.io / registry.k8s.io 无加速，需 NAT 出口才能拉取 argo / ingress-nginx 等镜像。
# 华为云在创建 NAT 网关时会自动在默认路由表写入 0.0.0.0/0 -> NAT 路由；
# 但本版本 provider 不支持在 nat_gateway 上内联关联 EIP（nat_gateway_address
# 与 vpc_eip.port_id 均不可写），故用 null_resource + 官方 API 将 EIP 绑定到
# NAT 网关端口（幂等，可重复执行）。
# ============================================================================
resource "huaweicloud_vpc_eip" "nat" {
  publicip {
    type = "5_bgp"
  }
  bandwidth {
    name        = "${var.project_name}-nat-eip"
    size        = 5
    share_type  = "PER"
    charge_mode = "traffic"
  }
}

resource "huaweicloud_nat_gateway" "main" {
  name        = "${var.project_name}-nat"
  spec        = "1"
  vpc_id      = huaweicloud_vpc.main.id
  subnet_id   = huaweicloud_vpc_subnet.az1.id
  description = "NAT for CCE worker nodes to pull public container images"
}

# 将 NAT EIP 绑定到 NAT 网关端口（provider 不支持内联关联，用 API 补齐；幂等）
resource "null_resource" "nat_eip_bind" {
  depends_on = [huaweicloud_nat_gateway.main, huaweicloud_vpc_eip.nat]

  triggers = {
    nat_id = huaweicloud_nat_gateway.main.id
    eip_id = huaweicloud_vpc_eip.nat.id
  }

  provisioner "local-exec" {
    command = "python3 bind_nat_eip.py"
    environment = {
      HW_REGION      = var.region
      NAT_GATEWAY_ID = huaweicloud_nat_gateway.main.id
      NAT_EIP_ID     = huaweicloud_vpc_eip.nat.id
      NAT_PORT_IP    = huaweicloud_nat_gateway.main.ngport_ip_address
    }
  }
}

# ============================================================================
# 输出
# ============================================================================
output "cce_cluster_id" {
  value = huaweicloud_cce_cluster.main.id
}
output "cce_kubeconfig_url" {
  value = "hw cce get-credentials --cluster-id ${huaweicloud_cce_cluster.main.id} --kubeconfig ./kubeconfig.yaml"
}
output "obs_app_code_bucket" {
  value = huaweicloud_obs_bucket.app_code.bucket
}
output "obs_datalake_bucket" {
  value = huaweicloud_obs_bucket.datalake.bucket
}
output "ingress_elb_eip" {
  value = huaweicloud_vpc_eip.ingress.address
}
output "swr_org" {
  value = huaweicloud_swr_organization.main.name
}
output "csms_secret_name" {
  value = huaweicloud_csms_secret.jhub.name
}
