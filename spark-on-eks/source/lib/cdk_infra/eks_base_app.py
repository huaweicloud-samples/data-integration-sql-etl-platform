# // Copyright 本开源样例贡献者. All Rights Reserved.
# // SPDX-License-Identifier: MIT-0
from hw_cdk import CloudStack
from constructs import Construct
from hw_cdk.aws_eks import ICluster, KubernetesManifest
from lib.util.manifest_reader import *
import os

class EksBaseAppConst(Construct):
    @property
    def secret_created(self):
        return self._ext_secret    

    def __init__(self,scope: Construct, id: str, eks_cluster: ICluster, **kwargs,) -> None:
        super().__init__(scope, id, **kwargs)

        source_dir=os.path.split(os.environ['VIRTUAL_ENV'])[0]+'/source'
        
        # Add ALB ingress controller to 容器集群服务
        self._alb = eks_cluster.add_helm_chart('ALBChart',
            chart='cce-ingress-nginx',
            repository='https://charts.example.com/cce',
            release='alb',
            version='1.5.5',
            create_namespace=False,
            namespace='kube-system',
            values=load_yaml_replace_var_local(source_dir+'/app_resources/alb-values.yaml',
                fields={
                    "{{region_name}}": CloudStack.REGION, 
                    "{{cluster_name}}": eks_cluster.cluster_name, 
                    "{{vpc_id}}": eks_cluster.vpc.vpc_id
                }
            )
        )
        # Add Cluster Autoscaler to 容器集群服务
        _var_mapping = {
            "{{region_name}}": CloudStack.REGION, 
            "{{cluster_name}}": eks_cluster.cluster_name, 
        }
        eks_cluster.add_helm_chart('ClusterAutoScaler',
            chart='cluster-autoscaler',
            repository='https://kubernetes.github.io/autoscaler',
            release='nodescaler',
            create_namespace=False,
            namespace='kube-system',
            values=load_yaml_replace_var_local(source_dir+'/app_resources/autoscaler-values.yaml',_var_mapping)
        )

        # Add container insight (云监控 Log) to 容器集群服务
        KubernetesManifest(self,'ContainerInsight',
            cluster=eks_cluster, 
            manifest=load_yaml_replace_var_remotely('https://raw.githubusercontent.com/huaweicloud/container-observability/main/manifests/container-insights-quickstart.yaml', 
                    fields=_var_mapping,
                    multi_resource=True
            )
        )
        # Add external secrets controller to 容器集群服务
        self._ext_secret = eks_cluster.add_helm_chart('SecretContrChart',
            chart='kubernetes-external-secrets',
            repository='https://external-secrets.github.io/kubernetes-external-secrets/',
            release='external-secrets',
            create_namespace=False,
            namespace='kube-system',
            values=load_yaml_replace_var_local(source_dir+'/app_resources/ex-secret-values.yaml',
                fields={
                    '{{region_name}}': CloudStack.REGION
                }
            )
        )
        self._ext_secret.node.add_dependency(self._alb)
        # Add Spark Operator to 容器集群服务
        eks_cluster.add_helm_chart('SparkOperatorChart',
            chart='spark-operator',
            repository='https://kubeflow.github.io/spark-operator',
            release='spark-operator',
            version='1.1.27',
            create_namespace=True,
            values=load_yaml_replace_var_local(source_dir+'/app_resources/spark-operator-values.yaml',fields={'':''})
        )