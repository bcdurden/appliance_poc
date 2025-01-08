# RKE2 and Rancher with Fleet

This doc will cover the install of RKE2 and Rancher via Fleet only. There is no Terraform, ansible, or CAPI involved. In fact this is the absolute EASIEST way to install Rancher onto Harvester. This doc also assumes that the steps defined in the parent doc have been followed regarding Harvester's configuration (specifically the SSH key, VM image, and VM network). Note this demonstration is NOT airgapped though it can be easily enough.

## Brief Explanation
This method is new and takes advantage of the new Fleet integration with Harvester. We'll be using the HelmChart we used from the [RKE2 with Helm](../rke2_helm/) method here. There are two ways to do this, one requires having a git repo available within your envionment (or from the internet if you have access) and the other doesn't require git. 

Creating the second version is a bit tedious unless you can create the first version. The reason for this is because the first version uses Fleet's GitOps capability by referencing a remote repo that contains both the RKE2 helmchart and values. When consumed this data creates a `Bundle` object inside of Harvester/Fleet. Fleet uses Bundle objects to do automation work as a Bundle describes a set of discovered resources and how to process them. The second method here uses a `Bundle` directly and creating them can be a little toilsome.

To avoid that issue, I'm including a prebuilt one that contains the helmchart in its current state as of Jan 8th 2025. The `Bundle` file is the [Management Cluster config](./mgmt.yaml) file. 

## Preconfig Requirements

Currently, Harvster's loadbalancer works well but has a very prescriptive `ValidatingWebhook` that breaks different cloud patterns of LoadBalancer management. That issue is being rectified in 1.4.x, but it is easy to remove the webhook for the LoadBalancer using the command below:

```bash
kubectl delete ValidatingWebhookConfigurations harvester-load-balancer-webhook
```

Ensure you have an OS image loaded in Harvester. I'm using Ubuntu 22.04 because it works well out of the box without any changes, some of my config values included for the cluser assume this.

### Cluster Config
Edit the [Management Cluster config](./mgmt.yaml) file and set all values appropriately. Note here, unlike the pure helm version, we need to inject some values ourselves. The values we are editing reside in the yaml path `.spec.helm.values`.

Ensure these are set correctly:
* LoadBalancer values (`control_plane.loadbalancer_gateway` `control_plane.loadbalancer_subnet` `control_plane.vip`) -- ensure your LB IP settings are on the host/mgmt network for now unless you want to add extra routing rules
* Static IP Network Config (`control_plane.network`) -- note this is an Ubuntu example, Rocky and RHEL look a little different
* SSH public key (`ssh_pub_key`) -- Ensure you have ownership of the key pair, we'll need it to hop onto the node if something goes wrong
* VM specs (`control_plane.cpu_count` `control_plane.memory_gb`)
* Network Name (`network_name`) -- the VM Network you created in Harvester that will host your VMs
* VM Image Name (`vm.image`) -- the name of the VM image you're using for your nodes.
* Rancher URL (`control_plane.files[].content`)-- set the embedded rancher URL to a domain you control or at least one you can set in your local `/etc/hosts`

### Install

Installation is EASY. Just point your kube context to your Harvester cluster and fire away!
```bash
kubectl apply -f mgmt.yaml
```

Once the `Bundle` is created in Harvester, Fleet will immediately begin trying to install the embedded HelmChart. You should quickly see VMs start spinning up in Harvester, assuming your config values were correct.

Once helm has installed the release that creates the RKE2 cluster, you can wait for the first node to come online (it waits for cloud-init). Set the env vars correctly.
```bash
export SSH_PRIVATE_KEY=$HOME/.ssh/command
export RKE2_NODE_IP=10.2.0.21
ssh -i $SSH_PRIVATE_KEY -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$RKE2_NODE_IP "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for Cloud-Init...'; sleep 5; done"
```

So the install process goes like this: RKE2 -> Cert-manager -> Rancher. On my system, this takes about 7min to install in total and I am not doing any airgap stuff. When airgapping everything, it is significantly faster (5min or less).

If you want to peak at progress, you can use the kubeconfig of the cluster once it is up to watch for Rancher starting. After Rancher has started, congrats, you're done!

#### Optional Kubeconfig step
Once the first node is in a ready state, you can fetch the kubeconfig from the node using the below command and set the VIP value inside it. Set the env vars correctly.
```bash
export SSH_PRIVATE_KEY=$HOME/.ssh/infrakey
export RKE2_NODE_IP=10.2.0.21
export VIP=$(helm get values mgmt-cluster | grep vip: | awk '{printf $2}')
ssh -i $SSH_PRIVATE_KEY -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ubuntu@$RKE2_NODE_IP "sudo cat /etc/rancher/rke2/rke2.yaml" 2> /dev/null | \
sed "s/127.0.0.1/${VIP}/g" > kube.yaml
chmod 600 kube.yaml
```

From here, the kubeconfig file is `kube.yaml`, you can watch the nodes or pods until everything comes up
```bash
watch kubectl --kubeconfig kube.yaml get nodes
```
