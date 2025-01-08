# Dell Appliance Docs

## SBOM
* Harvester Government 1.3.2 or Harvester Community 1.3.2
* Harbor
* Gitea
* Keycloak
* Rancher 2.9.x (or 2.10.x)

## Kubernetes Basics
* [kubecm](https://kubecm.cloud)
* helm
* kubectl
* clusterctl (for CAPI)
* [k3d](https://k3d.io/stable/) (for CAPI)

## DNS
* Wildcard DNS entry for Ingress (ie. *.mycluster.com)

## Certificates

There are several methods of creating certs, the easiest path is using `cert-manager` to do so. Sometimes, however, this isn't possible. So using pre-created certs from another source is perfectly viable. This section isn't going to cover creation of certs or diving into the finer points there as its a heady topic. But it is suggested to use `cert-manager` as it is a K8S-native way of managing certs easily, especially for PoCs.

### Cert-Manager

[Cert-manager](https://cert-manager.io) is an open-source Kubernetes add-on that automates the management and issuance of TLS/SSL certificates. It simplifies securing communication between services by automating certificate lifecycle tasks.

Key Features:

* Automates certificate issuance with CAs (e.g., Let’s Encrypt, Vault, self-signed).
* Handles automatic renewal of expiring certificates.
* Integrates with Kubernetes resources like Ingress controllers.
* Supports ACME protocol for Let’s Encrypt certificates.
* Provides CRDs like Certificate, Issuer, and ClusterIssuer.

## Install

This will cover the manual install process including tools as part of the appliance stack. The intention is later to switch to a more automated install once familiarity is built up and we pass the POC stage. Be aware that it's not only possible, but actually easy, to do a full automated install of Harvester as well as anything else running on top of it.

This install path will be quasi-airgapped. A full airgap requires a few extra steps such as image caching for Harbor that can be covered in a more advanced/complete installation process.

Also, this install will be a full install. There also exists a path to install binaries only so that when the node boots, the install automatically starts without requiring the ISO mounted to USB or other media.

### Harvester Government

Harvester Government is a paid product from Rancher Government Solutions (RGS). This includes enablement of the FIPS kernel within the immutable OS (Elemental) as well as pre-stigging of Harvester, including all the components comprising it (Elemental, RKE2, Longhorn, Multus, etc).

Install on two main nodes via ISO. Ensure static addresses set including VIP. Minimum requirement of one network for management. For IO performance, ensure secondary uplink is available to offload storage replication.

To acquire the ISO for this install, please contact RGS for details. The community version can also be used here instead as a PoC, but will not have all of the security features available. See [github releases](https://github.com/harvester/harvester/releases). As of this writing, the current Harvester release is 1.3.2. The release of 1.4.0 is emminent.

Note: Everything in this writeup can be done with Harvester Comunity. When it comes time to validate hardware and do more advanced field-testing, it is suggested to use the true Harvester Government release as it has all of the FIPS 140-3, security controls, and STIG pre-applied.

#### Witness Node

Connecting to the witness node is a manual step as it does not support PXE booting and does not have the appropriate drivers to begin a Harvester install.

Use a USB-A to MicroUSB cable plugged into one of the XR4000Z blades.

1. The Nano node Power is managed via one of the two other nodes iDrac. System -> Witness Server -> Power Control Settings.

2. Attach a Serial Console to the witness-node (micro-usb).

    * If the customer has cu, then they can use that from a laptop or similar
    * If not, attach the serial cable to one of the Dell nodes already running Harvester, (this one is a USB to Micro USB) then
        * SSH into the physical Harvester node connected to the witness node `ssh rancher@myip`
        * Go into superuser mode with `sudo su`
        * Run `docker run -it --device=/dev/ttyUSB0:/dev/ttyUSB0 opensuse/leap /bin/bash` to enter a running shell
        * Within the shell, install the necessary apps: `zypper install uucp`
        * Set the permission for the USB device: `chmod 666 /dev/ttyUSB0`
        * Run the terminal screen with: `cu -l /dev/ttyUSB0 -s 115200`
    * Powercycle the witness node

3. At the grub screen, edit the VGA 1024x768 entry by hitting `e` and add `console=ttyS4,115200` at the end of the main grub line (do not remove the existing tty1 entry). This would put it in a serial screen of tty4. Hit Ctrl-X to boot using the new arguments.

4. The witness node should boot off the USB device and print a lot of linux boot text. If it stops and doesn't progress after 10-20seconds, you've done something wrong. Go back and try again.

5. Login via the terminal with rancher:rancher, get superuser via `sudo su -` and then set the terminal size `setterm --resize`

6. Execute `start-installer.sh`, skip the size warning (the witness node does not have the same requirements as a full node) and choose the `Join an Existing Cluster`, the `Witness` role, and choose the 900GB Disk. Ensure both disk choices use the 900GB disk and using the default amount of storage is fine.

7. At the end of the installation, remove the installation media/USB disk or the system won't boot into the available disk.

#### Harvester Configuration
There are few items in Harvester that should be configured out of the gate. Most notably these are the `ReadWriteMany` storage class, any VM images you wish to preload, as well as configuration of the networking.

#### Longhorn Storage
By default, in Harvester's Longhorn, the CPU reservation percentage is set at 25%. In nearly all Edge use cases, this is considered overkill. It is suggested to dial this down to a value you find more useful. It can always be raised later if it is found that Longhorn is being CPU starved to complete replication tasks.

Enabling Developer UIs like Longhorn require going into the profile config menu. Click the top-right of Harvester on the profile picture and select `Preferences`. From there, scroll down and select `Enable Extension developer features`. 

Go to the main Harvester dashboard by clicking the flag or logo in the top left. Click `Support` at the bottom left of the screen. From here you can choose the Longhorn UI and it will open in a new window.

Via the Longhorn UI, this value can be set in the General Settings. For Edge use cases that the XR4000 will run into, it likely does not need to be higher than 5%.

##### Acquiring Harvester kubeconfig
The Harvester API is very similar to the Rancher API though some of the paths are different. But it can be used to generate a service-account-based kubeconfig based around the credentials you provide. If you've already created this file at some other point in time, you can skip this step. Note that this file is different than the one that resides on the Harvester node itself. This one has an expiry and is service-account based.

Like the Rancher API, the Harvester API uses the same API token mechanism at a different endpoint. So I'm going to define a few environment variables here. I need my harvester VIP and the admin password:
```bash
export HARVESTER_VIP=86.75.30.9
export PASSWORD="mypassword"
```

Next I generate the API token with these values:
```bash
export TOKEN=$(curl -sk -X POST https://$HARVESTER_VIP/v3-public/localProviders/local?action=login -H 'content-type: application/json' -d '{"username":"admin","password":"'$PASSWORD'"}' | jq -r '.token')
```

With this token, I can make Harvester API calls, like requesting creation of a new kubeconfig for my use:
```bash
curl -sk https://$HARVESTER_VIP/v1/management.cattle.io.clusters/local?action=generateKubeconfig -H "Authorization: Bearer ${TOKEN}" -X POST -H 'content-type: application/json' | jq -r .config > kube.yaml
chmod 600 kube.yaml
```

Now I have a kubeconfig defined in `kube.yaml` and can make kubectl commands using it later!

##### SSH KeyPair
Create an SSH keypair locally on your workstation or reuse one. Harvester needs the public key to create a `KeyPair` object that it can use for injection/reference.

Set your `SSH_PUBLIC_KEY_PATH` field in the below command to point at your public key:

```bash
export SSH_PUBLIC_KEY_PATH=$(cat $HOME/.ssh/command.pub)
cat harvester/ssh_key.yaml | envsubst | kubectl apply -f -
```

##### StorageClasses

There are several `StorageClasses` that need to be created for the XR4000Z. One is the default class with replica counts set to 2 as well as a `ReadWriteMany` one.f

Create the `StorageClasses` [here](./harvester/sc.yaml)

```bash
kubectl apply -f harvester/sc.yaml
```

##### Network

Harvester uses a similar network topology to other established solutions and it is based on Multus. There are three key components:
* Cluster Network - Underhood defines a network bridge that is shared among all nodes, equivalent to a Distributed Switch in vSphere
* Cluster Network Config - Underhood attaches uplinks and handles bonding rules, equivalent to an Uplink Port Group in vSphere
* VM Networks - Defines Layer2 network, including VLANs and DHCP params, equivalent to Distributed Port Group in vSphere

Networking config can get complex quickly depending on the customer's intended solution. In order to keep things simple and reduce dependencies for demos on Layer3 VLAN routing, we will just use an 'untagged' VM network and stick to the management Cluster Network (which is predefined and is tied to the management uplink chosen during installation).

To create this VM network, one can go to the UI and create a VM-network that is 'untagged', or you can just apply this yaml using `kubectl`:

```bash
kubectl apply -f harvester/host_network.yaml
```

##### VM Image

Creating VMs requires a cloud-init friendly VM to be stored within Harvester when using Linux. Nearly any linux-based distribution has these packages available. Several more prominent distributions supply cloud-friendly versions of their distributions as part of their release cadence.

For ease of use, we will use Ubuntu for now. VM Images can be created manually within the UI and either be uploaded to Harvsester itself or a URL be provided for Harvester to download from. The latter tends to be more reliable in the real-world due to the nature of complex networks that interrupt the websocket connection that the UI uses for uploads. 

Instead of using the UI, we will create one from a [yaml definition](harvester/image.yaml). Within this definition, we are setting the replica count to be 2. This is done because the XR4000Z that is part of this POC only has two worker nodes with a witness node. This means that we do not have a 3rd volume storage location. Because of this, the volume would come up as 'degraded'. We will set this to 2 to avoid the false positive and ensure everything runs smoothy.

Apply the VM image here:
```bash
kubectl apply -f harvester/image.yaml
```

##### CPU Reservation for Longhorn
TODO

##### Disk Reservation and overprovisioning for Longhorn
TODO

### Cert-Manager
TODO

#### Ingress Certificate Generation
TODO

### Harbor

Harbor is the most common container regsitry management solution for Kubernetes and contains many features that enable supply chain security processes. It uses a helm chart to install.

Harbor uses a helmchart to install and the only real config item that differs from install to install is the hostname of the registry itself. This is a DNS entry that needs to be resolvable either via local `/etc/hosts` or via your airgapped DNS zone. There are a variety of sources of this helmchart, I use the bitnami version at it is built with stronger security requirements in mind as well as targeting an enterprise deployment.

Typically to inject this URL without making the configuration too bespoke, I use `envsubst` to do an environment variable substitition and output the result of that to `helm` when doing the install.

First add the bitnami helm repo:
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
```

Ensure your kube context is pointed at the Harvester cluster, and install Harbor. I use the `upgrade` command to make this install command repeatable in case something fails for whatever reason. Note I am using `envsubst` as described to pipe the results to helm via stdin.
```bash
export BASE_URL=dell.sienarfleet.systems
cat harbor/values.yaml | envsubst | \
helm upgrade -i harbor -n harbor --create-namespace bitnami/harbor -f -
```

### Gitea

Gitea is a lightweight and cloud-native Git Repository Management application. It is designed to be very compatible with Github and the APIs build around Github. Github Actions work within Gitea without modification and it is designed to run both on-prem and in the cloud.

Gitea has an ingress endpoint for using the UI as well as a LoadBalancer endpoint for SSH traffic. Ensure both are defined and resolvable within your DNS

Add the Gitea helm repo:
```bash
helm repo add gitea https://dl.gitea.com/charts
```

```bash
export BASE_URL=dell.sienarfleet.systems
export GITEA_SSH_IP=10.2.0.15
cat gitea/values.yaml | envsubst | \
helm upgrade -i gitea -n git --create-namespace gitea/gitea -f -
```

### RKE2 + Rancher 

As of now, (Nov16-2024), the current recommended way to install Rancher onto Harvester is via a guest cluster. This pattern is common and considered best practice among all infrastructures. This usually involves 1, 3, or 5 VMs running as RKE2 nodes in a control-plane/worker hybrid format. This is a specialized cluster designed to manage all other clusters and typically we do do not 

There are quite a few methods of installing RKE2 and Harvester being RKE2 at its core adds even more options. The three newer methods involve using Kubernetes APIs to create this RKE2 cluster (and in some cases install Rancher!). Harvester being Kubernetes means VMs and other resources can be described using yaml definitions just like a typical containerized application. With this, we can use a simple helmchart to deploy a cluster directly into Harvester. That method is [defined here](rke2_helm/readme.md). Currently the helm method is the most stable of the new methods.

Using the helmchart method as a baseline, we can also utilize Fleet (which is preinstalled into Harvester) to install Rancher and RKE2 all at once. This allows for a single kubectl command to install Rancher onto Harvester! See the writeup [defined here](rke2_fleet/readme.md).

The third method is using CAPI (Cluster API) which is basically an in-tree cousin of Rancher's node provisioners. We can kickstart it using a bootstrap cluster on a local workstation. From there, CAPI will build an RKE2 cluster on Harvester based on our specifications. CAPI also provides us a way to declaratively describe resources on the clusters, and we will use that to install Cert-Manager and Rancher itself onto that cluster. Harvester's CAPI provider is still in alpha currently and so there may be bugs with this approach. [Click Here](rke2/README.md)

### Advanced Installation

#### Overcommit Configuration

For a dive into how overcommit works and how to change it in Harvester, see [this gist](https://gist.github.com/bcdurden/f30b7a80bac825f0b34267df99ceff6e#file-longhorn_allocations-md)

Notes on custom ISO + config booting
Pre-caching images for services airgap

