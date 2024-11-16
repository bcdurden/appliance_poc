#!/bin/bash

export CLUSTER_NAME=$(yq .CLUSTER_NAME clusterctl.yaml)
clusterctl generate cluster --from rancher_template.yaml \
  --config clusterctl.yaml \
  ${CLUSTER_NAME} \
  | kubectl apply -f -