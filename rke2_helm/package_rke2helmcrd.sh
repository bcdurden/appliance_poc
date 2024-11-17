#!/bin/bash

pushd charts/rke2
    tar czvf /tmp/rke2.tar.gz . 
popd

if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    export CHART_B64=$(cat /tmp/rke2.tar.gz | base64)
else
    # Linux
    export CHART_B64=$(cat /tmp/rke2.tar.gz | base64 -w0)
fi

rm /tmp/rke2.tar.gz

yq '.spec.valuesContent = load_str("values.yaml")' rke2_helmcrd_template.yaml | yq '.spec.chartContent = strenv(CHART_B64)' > rke2helmcrd.yaml

