#!/bin/bash

k3d cluster create

export EXP_CLUSTER_RESOURCE_SET=true
export CLUSTER_TOPOLOGY=true
clusterctl --config clusterctl.yaml init -i harvester --bootstrap rke2 --control-plane rke2

kubectl rollout status deployment --timeout=90s -n rke2-bootstrap-system rke2-bootstrap-controller-manager

kubectl rollout status deployment --timeout=90s -n rke2-control-plane-system rke2-control-plane-controller-manager

kubectl rollout status deployment --timeout=90s -n caphv-system caphv-controller-manager

export HARVESTER_CONTEXT_NAME=dell
kubectl config use-context ${HARVESTER_CONTEXT_NAME}
export HARVESTER_KUBECONFIG_B64=$(kubectl config use-context ${HARVESTER_CONTEXT_NAME} &>/dev/null && kubectl config view --minify --flatten | yq '.contexts[0].name = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.current-context = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.clusters[0].name = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.contexts[0].context.cluster = "'${HARVESTER_CONTEXT_NAME}'"' | base64 -w0); \
kubectl config use-context k3d-k3s-default

export HARVESTER_CONTEXT_NAME=dell
kubectl config use-context ${HARVESTER_CONTEXT_NAME}
export LOAD_BALANCER_IP=$(yq .LOAD_BALANCER_IP clusterctl.yaml)
export LOAD_BALANCER_GATEWAY=$(yq .LOAD_BALANCER_GATEWAY clusterctl.yaml)
export LOAD_BALANCER_CIDR=$(yq .LOAD_BALANCER_CIDR clusterctl.yaml)
cat ippool.yaml | envsubst | kubectl apply -f -
kubectl config use-context k3d-k3s-default

export CLUSTER_NAME=$(yq .CLUSTER_NAME clusterctl.yaml)
clusterctl generate cluster --from rke2_template.yaml \
  --config clusterctl.yaml \
  ${CLUSTER_NAME} \
  | kubectl apply -f -