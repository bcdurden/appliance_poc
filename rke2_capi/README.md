# Experimental Addon for Rancher on RKE2 Autoinstall

This will cover an experimental and PoC-grade addon for Harvester that can be used to install an RKE2 guest cluster into Harvester directly without requiring any external tools or dependencies outside of what Harvester comes with. This installs a full-blown version of Rancher onto a guest cluster. In the past you would use Terraform or Ansible for this, but now we do not need it.

This solution uses Harvester to spin up a temporary vcluster and uses that as a CAPI bootstrap cluster via the CAPI operator. From there it uses the RKE2 ControlPlane and Bootstrap CAPI providers along with the Harvester Infrastructure provider (currently in beta)

There are limitations here:
* The Harvester Infra Provider has a few limitations including
  * Requiring embedding a Harvester kubeconfig with a very specific name in base64 format
  * CPU counts do not reflect actual CPU consumption due to a provisioning bug (desired cpu cores end up being pasted into sockets and threads)
  * LoadBalancing requires usage of DHCP and cannot do static IP assignment inline (yet)
  * Using agentConfig.additionalUserData field in RKE2ControlPlane objects will break the Harvester provider
  * Currently there is no way to manage static IP addresses for control plane nodes
  * The VM instances in Harvester have hardcoded cloud-init configurations and do not support any flags such as UEFI, so UEFI-only OS's such as Rocky will likely not work
* The Harvester Addon has hardcoded UI elements, so using a custom Addon will not render any fields and requires manual yaml editing

### Known Issues
* vcluster uses stateful sets and does not by default clean up its volumes, this can cause issues if you repeatedly use it as the existing kubernetes state of vcluster will be resumed vs being reinstalled. So ensure you delete the PVC

## Howto

Install the addon into the Harvester cluster as-is:

```bash
kubectl apply -f addon.yaml
```

Or if you prefer to skip the addon steps, just use the [helmchart file](./helmchart.yaml) directly (ensure you edit it properly)

```bash
kubectl apply -f helmchart.yaml
```

Once installed, go to the Harvester Addons menu under Advanced->Addons and click the `...` menu to the right on the `rancher-embedded` addon. Click `Edit Config`.

Click the `Enable` button and then select `Edit Yaml` at the bottom. From here is where you will edit the values in the addon at the top.

The values to edit are:
```yaml
    vm_network_name: ""
    ssh_keypair: ""
    vm_image_name: ""
    vm_default_user: ""
    harvester_vip: ""
    rancher_url: ""
    harvester_kubeconfig_b64: ""
```

Everything should be obvious here except for the harvester kubeconfig. The easiest path is to go to download the harvester kubeconfig file and then convert it into base64.

On Linux, base64 requires `-w0` and MacOS does not
```bash
#linux
cat ~/Downloads/local.yaml | base64 -w0
#macos
cat ~/Downloads/local.yaml | base64
```

Once the values are placed into the appropriate fields, hit 'save'. 

### Progress

Underhood, the first thing that will happen is Harvester will attempt to install a vcluster instance into the bare metal RKE2 cluster.

After the cluster starts, it will run the pods in the local Harvester cluster using specific names and also within the same namespace as the vcluster instance. Using this addon will place that into default for now.

You can watch progress using `watch kubectl get po`. It takes a few minutes for all of the orchestration to work including the CAPI components/providers to be installed. 

Once everything is running it will look something like this:
```console
❯ kubectl get po
NAME                                                              READY   STATUS      RESTARTS        AGE
act-runner-55746f5496-tjd7p                                       1/1     Running     55 (61m ago)    5h26m
bootstrap-cluster-cluster-api-operator-bfcf86f56-7vf-0f378249f8   1/1     Running     0               32m
caphv-controller-manager-b64f46f7b-mbkhf-x-caphv-sys-032300ba48   2/2     Running     0               31m
capi-controller-manager-59f959f88c-8q4r4-x-capi-syst-e7732a666f   1/1     Running     0               31m
cert-manager-5d58d69944-wvg5t-x-cert-manager-x-rancher-embedded   1/1     Running     0               32m
cert-manager-cainjector-54985976df-4vzwg-x-cert-mana-2144030793   1/1     Running     0               32m
cert-manager-webhook-5fcfcd455-mxlhf-x-cert-manager--d1f937cca4   1/1     Running     0               32m
coredns-5964bd6fd4-f8j5q-x-kube-system-x-rancher-embedded         1/1     Running     0               32m
helm-install-bootstrap-cluster-xp4z4-x-default-x-ran-2182ba190e   0/1     Completed   2               32m
helm-install-cert-manager-5l2fn-x-default-x-rancher-embedded      0/1     Completed   0               32m
helm-install-rancher-embedded-psc98                               0/1     Completed   0               33m
homepage-6d76d9dc47-2jdgx                                         1/1     Running     4 (5h28m ago)   4d4h
rancher-embedded-0                                                1/1     Running     0               33m
rke2-bootstrap-controller-manager-6f7d89cc94-6465s-x-1f18bbe86b   1/1     Running     0               31m
rke2-control-plane-controller-manager-5dbcdd76f4-dz6-b566dd9bbf   1/1     Running     0               31m
```

The CAPI provisioner should start creating Harvester VMs as RKE2 nodes soon after and they will show up in the UI or as virt-launchers:

```console
virt-launcher-rke2-mgmt-cp-machine-9cxnq-vcwrh                    2/2     Running     0               31m
virt-launcher-rke2-mgmt-cp-machine-hjqlm-hlcrq                    2/2     Running     0               25m
virt-launcher-rke2-mgmt-cp-machine-w6hmm-8sd86                    2/2     Running     0               28m
```

After a time the CAPI provisioner will create a LoadBalancer object in Harvester. For now this is DHCP, so inspect your loadbalancers to get the IP in the UI. Or just use `kubectl`:
```console
❯ kubectl get loadbalancer
NAME                      DESCRIPTION                              WORKLOADTYPE   IPAM   ADDRESS     AGE
default-rke2-mgmt-hv-lb   Load Balancer for cluster rke2-mgmt-hv   vm             dhcp   10.2.0.76   33m
```

Note my IP is 10.2.0.76. So I will either make a DNS entry for my rancher URL or edit `/etc/hosts` as a quick hack. Once that change is made, the Rancher UI should present itself. The bootstrap password is `admin`


