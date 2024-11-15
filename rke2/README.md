# RKE2 Cluster Creation

This doc pertains to the management cluster that must be installed on top of Harvester as a guest cluster in order to run Rancher in a highly-available and airgap friendly mode.

There are many paths to installing RKE2 into Harvester. It can be done manually via VM creation and installing RKE2 directly on top. We can use Terraform or Ansible playbooks in order to provision the cluster. And the newer way is using ClusterAPI (CAPI) to deploy RKE2 declaratively as a Kubernetes resource on Harvster.

Given the new path with CAPI, it is the future way of managing clusters both in the direction of Rancher but also how the industry is trending, I'm going to cover that here instead of the other options.

## Dependencies

CAPI requires a bootstrap cluster to exist. You can use KinD or k3d. I'll use k3d here. There are also other tools associated

* Docker
* K3D
* kubectl
* clusterctl
* Base VM image
* Harvester SSH key generated
* Harvester Network created
* Harvester kubeconfig is in `$HOME/.kube/config`
* envsubst (usually included in bash/zsh)

## Configuration

CAPI functions based on a template + values file pattern. The template uses simple bash-like variables that `clusterctl` will edit in place based on either environment variables defined at runtime or based on a configuration yaml file.

That configuration file is [clusterctl.yaml](./clusterctl.yaml). Pay particular attention to the network and vm image names as they correspond to pre-existing objects inside of Harvester.

## Scripted Install Process (RKE2 and Rancher)

Using the below manual steps, two scripts have been created to install RKE2 and Rancher using CAPI. This assumes values have been defined properly in [clusterctl.yaml](./clusterctl.yaml)

To get a better understanding of how these scripts work (they are not intelligent or stateful), its recommended you try the manual route below first. I have placed a 7min sleep inbetween the commands because that is about how long it takes for the 3rd node to come up in an unoptimized state. When working in an airgap, this process can be shrunk down far and the steps also combined with some webhooks if necessary.  But I would consider keeping them split because there is no CR reference dependencies between the two beyond a cluster name. So the rancher template could arguably work on any infra provider. I'm trying to keep it simple right now, so we'll stick with this.

```bash
./install_rke2.sh
sleep 420
./install_rancher.sh
```

## Manual Install Process (RKE2)

First, create your K3D boostrap cluster:
```bash
k3d cluster create
```

Next, install the CAPI dependencies using clusterctl:
```bash
export EXP_CLUSTER_RESOURCE_SET=true
export CLUSTER_TOPOLOGY=true
clusterctl --config clusterctl.yaml init -i harvester --bootstrap rke2 --control-plane rke2
```

The CAPI components will now install, you can run the below commands to wait:
```bash
kubectl rollout status deployment --timeout=90s -n rke2-bootstrap-system rke2-bootstrap-controller-manager
kubectl rollout status deployment --timeout=90s -n rke2-control-plane-system rke2-control-plane-controller-manager
kubectl rollout status deployment --timeout=90s -n caphv-system caphv-controller-manager
```

Once CAPI components have installed, you can use `clusterctl` to generate the Kubernetes configuration and apply it to your bootstrap cluster. You can always output this to a file and then apply separately if you want to inspect. 

First, the Harvester kubeconfig needs to be grabbed and converted into a proper format. That can be done with this snippet (change the `HARVESTER_CLUSTER_NAME` variable to whatever the cluster context name is for your Harvester cluster):

```bash
export HARVESTER_CONTEXT_NAME=dell
kubectl config use-context ${HARVESTER_CONTEXT_NAME}
export HARVESTER_KUBECONFIG_B64=$(kubectl config use-context ${HARVESTER_CONTEXT_NAME} &>/dev/null && kubectl config view --minify --flatten | yq '.contexts[0].name = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.current-context = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.clusters[0].name = "'${HARVESTER_CONTEXT_NAME}'"' | yq '.contexts[0].context.cluster = "'${HARVESTER_CONTEXT_NAME}'"' | base64 -w0); \
kubectl config use-context k3d-k3s-default
```

We also need to create the IP Pool in Harvester. In the future this step will not be necessary as ipPool definitions inline will be implemented. Right now we need to create an IPPool object in our Harvester cluster that defines valid IPs for loadbalancing. Since this is a single LB pool, the IPPool will define one IP address only. Note I'm defining the IPs inline below, so you will need to adjust. But the scripts above will use `yq` to pull the values from the [clusterctl.yaml](./clusterctl.yaml) file instead.

To apply, we need to switch to the harvester cluster and apply the [ip_pool cr](./ippool.yaml):

```bash
export HARVESTER_CONTEXT_NAME=dell
kubectl config use-context ${HARVESTER_CONTEXT_NAME}
export LOAD_BALANCER_IP=10.2.0.3
export LOAD_BALANCER_GATEWAY=10.2.0.1
export LOAD_BALANCER_CIDR=10.2.0.0/24
cat ippool.yaml | envsubst | kubectl apply -f -
kubectl config use-context k3d-k3s-default
```

Now that the credentials have been grabbed, `clusterctl` can be run and the output piped to `kubectl` for creation:

```bash
export CLUSTER_NAME=rke2-mgmt
clusterctl generate cluster --from rke2_template.yaml \
  --config clusterctl.yaml \
  ${CLUSTER_NAME} \
  | kubectl apply -f -
```

As the cluster is created, the VM creation can be seen in the Harvester console but the more granular status can be viewed using `clusterctl`

```bash
clusterctl describe cluster ${CLUSTER_NAME}
```

## Install Process (Rancher)

Once the cluster is up and running, its very easy to install Rancher. In fact you don't need the helm cli at all, you can just take advantage of `ClusterResourceSet` CRs. We will create one that includes the helmchart CRs for both cert-manager and rancher. For now these pull from the internet but the chart can either be declared inline or referenced elsewhere for airgap friendliness.

```bash
export CLUSTER_NAME=rke2-mgmt
clusterctl generate cluster --from rancher_template.yaml \
  --config clusterctl.yaml \
  ${CLUSTER_NAME} \
  | kubectl apply -f -
```

# Cleanup

Once everything is complete, you can either copy the existing configuration out for a permanent copy or just delete the K3D cluster. Please note that when deleting the K3D cluster, it will not delete the cluster you just created with it. That can be done by the command below:

```bash
kubectl delete cluster rke2-mgmt
```

# Next Steps
Changing the nodes to be static IPs, likely involving cloud-init.