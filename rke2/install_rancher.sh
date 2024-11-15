#!/bin/bash

export CLUSTER_NAME=rke2-mgmt
clusterctl generate cluster --from rancher_template.yaml \
  --config clusterctl.yaml \
  ${CLUSTER_NAME} \
  | kubectl apply -f -