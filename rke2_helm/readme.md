# RKE2 and Rancher with Helm

This doc will cover the install of RKE2 and Rancher via Helm only. There is no Terraform, ansible, or CAPI involved. This doc also assumes that the steps defined in the parent doc have been followed regarding Harvester's configuration (specifically the SSH key, VM image, and VM network)

## Preconfig Requirements

Currently, Harvster's loadbalancer works well but has a very prescriptive `ValidatingWebhook` that breaks different cloud patterns of LoadBalancer management. That issue is being rectified in 1.4, but it is easy to remove the webhook for the LoadBalancer using the command below:

```bash
kubectl delete ValidatingWebhookConfigurations harvester-load-balancer-webhook
```

Edit the [RKE2 values](./values.yaml) file and set all values appropriately. IP addresses are set statically in this example and the SSH key you either create or reference needs to have a public/private pair.

Once the configuration is set, use the command below, editing where your public ssh key resides:
```bash
export SSH_KEY_PATH=$HOME/.ssh/command.pub
helm upgrade --install rke2-mgmt --set ssh_pub_key="$(cat $SSH_KEY_PATH)" -f values.yaml charts/rke2
```

Once helm has installed the release that creates the RKE2 cluster, you can wait for the first node to come online (it waits for cloud-init). Set the env vars correctly.
```bash
export SSH_PRIVATE_KEY=$HOME/.ssh/command
export RKE2_NODE_IP=10.10.0.36
ssh -i $SSH_PRIVATE_KEY -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$RKE2_NODE_IP "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 5; done"
```

Once the first node is in a ready state, you can fetch the kubeconfig from the node using the below command and set the VIP value inside it. Set the env vars correctly.
```bash
export SSH_PRIVATE_KEY=$HOME/.ssh/command
export RKE2_NODE_IP=10.10.0.36
export VIP=$(helm get values rke2-mgmt | grep vip: | awk '{printf $2}')
ssh -i $SSH_PRIVATE_KEY -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$RKE2_NODE_IP "sudo cat /etc/rancher/rke2/rke2.yaml" 2> /dev/null | \
sed "s/127.0.0.1/${VIP}/g" > kube.yaml
chmod 600 kube.yaml
```

From here, the kubeconfig file is `kube.yaml`, you can watch the nodes or pods until everything comes up
```bash
watch kubectl --kubeconfig kube.yaml get nodes
```

After all 3 nodes join and are in a ready state, you can use the cert-manager HelmChart CRD to make your cluster install cert-manager using its internal helm operator:
```bash
kubectl --kubeconfig kube.yaml apply -f certmanager.yaml --wait
```

After installing cert-manager, you can kick off Rancher. Edit the environment variables below to your liking. More complex tweaks can be made in the [rancher.yaml](./rancher.yaml) file.
```bash
export RANCHER_URL=rancher.dell.sienarfleet.systems
export RANCHER_REPLICAS=3
cat rancher.yaml | envsubst | kubectl --kubeconfig kube.yaml apply -f - --wait
```

From here, we need to snag the generated ingress TLS cert from Rancher, since it is using self-signed certs by default for this POC. We need to add them to the Harvester setting called `addtional-ca`
```bash
cert=$(kubectl --kubeconfig kube.yaml get secret -n cattle-system tls-rancher -o yaml | yq '.data."tls.crt"' | base64 -d)
kubectl get setting additional-ca -o yaml | yq '.value = "'$cert'"' | kubectl apply -f -
```

From here we can use the UI to put Harvester under Rancher's control.

## Carbide
As an alternative, the Carbie Helm Chart can be used to install Rancher on RKE2

To do this, you need to input your password and username into the environment variables

```bash
export RANCHER_URL=rancher.dell.sienarfleet.systems
export RANCHER_REPLICAS=3
cat carbide_rancher.yaml | envsubst | kubectl --kubeconfig kube.yaml apply -f - --wait
```