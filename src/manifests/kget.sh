#!/bin/bash
# 查看 spark 命名空间下作业状态（用于取证截图）
# 用法：设置 KUBECONFIG 后执行 bash kget.sh
KCFG="${KUBECONFIG:-./kubeconfig.yaml}"
kubectl --kubeconfig="$KCFG" -n spark get workflow 2>&1
