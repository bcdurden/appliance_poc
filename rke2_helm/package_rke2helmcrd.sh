#!/bin/bash

helm package charts/rke2

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    export CHART_B64=$(cat rke2-cluster*.tgz | base64)
else
    # Linux
    export CHART_B64=$(cat rke2-cluster*.tgz | base64 -w0)
fi


yq '.spec.valuesContent = load_str("values.yaml")' rke2_helmcrd_template.yaml | yq '.spec.chartContent = strenv(CHART_B64)' > rke2helmcrd.yaml

