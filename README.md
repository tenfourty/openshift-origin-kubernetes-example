# How to run OpenShift V3 on an existing Kubernetes Cluster

I'm a big fan of [Kubernetes](http://kubernetes.io/) and the ideas it brings to enable running Docker containers at scale. However if you've used Kubernetes you'll know that right now the tooling around it is pretty basic from a developer and application lifecycle perspective. [OpenShift V3](http://www.openshift.org/) builds on the concepts of Docker and Kubernetes to add some much needed higher level tooling and a Web UI that is really nice.

Here are just a few of the features that OpenShift Origin provides out of the box on top of a Kubernetes cluster:

- A rich set of role based policies out of the box
- Quota's and resource limits
- Source to Image - no need to know Docker, just build an image very efficiently from source
- Automated builds using on webhooks
- Application focused CLI, including:
  - Get logs for any of your running containers
  - Clever port forwarding for remote debugging

One of the things I wanted to do was to run a Kubernetes cluster in [Google Container Engine](https://cloud.google.com/container-engine/) but run OpenShift on top of it. This is because Container Engine does a great job of running my Kubernetes cluster - including handling autoscaling based on demand, networking and persistent volumes inside the cluster etc. All the plumbing stuff I don't want to have to care about when running a cluster.

When I looked into it I found this [example of running OpenShift-Origin as a pod in an existing Kubernetes cluster](https://github.com/GoogleCloudPlatform/kubernetes/tree/master/examples/openshift-origin) in the Kubernetes GitHub project, however it didn't work! So this is my basic guide in how to setup OpenShift V3 Origin to run on top of an existing Kubernetes cluster.

Like all things we do I'm standing on the shoulders of giant's and this tutorial was of course originally written by [Derek Carr](https://github.com/derekwaynecarr) in the [Kubernetes examples folder](https://github.com/GoogleCloudPlatform/kubernetes/tree/master/examples/openshift-origin) I've just tarted it up a bit.

### Step 0: Prerequisites

This example assumes that you have an understanding of Kubernetes and that you have forked [my example repository](https://github.com/tenfourty/openshift-origin-kubernetes-example).

The [Kubernetes Getting Started Guide](http://kubernetes.io/gettingstarted/) lists a few options, however for simplicity and robustness I'd reccommend using [Google Container Engine](https://cloud.google.com/container-engine/) to run your Kubernetes Cluster.

OpenShift Origin creates privileged containers when running Docker builds during the [source-to-image](https://github.com/openshift/source-to-image) process.

If you are following the getting started guide above and using a Salt based KUBERNETES_PROVIDER (**gce**, **vagrant**, **aws**), you should enable the ability to create privileged containers via the API.

```sh
$ cd kubernetes
$ vi cluster/saltbase/pillar/privilege.sls

# If true, allow privileged containers to be created by API
allow_privileged: true
```

Now spin up a cluster using your preferred KUBERNETES_PROVIDER

```sh
$ export KUBERNETES_PROVIDER=gce
$ cluster/kube-up.sh
```

Personally I setup my own cluster in Google Container Engine, if you take this approach you will need to follow these two guides:

- <https://cloud.google.com/container-engine/docs/before-you-begin>
- <https://cloud.google.com/container-engine/docs/clusters/operations>

Just one note about this approach - I haven't tried source-to-image but it may well fail in a vanila Google Container Engine cluster as [Google currently doesn't support creating privileged containers via the API](https://stackoverflow.com/questions/31124368/allow-privileged-containers-in-kubernetes-on-google-container-gke).

**Whichever way you choose to setup your cluster, make sure that kubectl and your ~/.kube/config is setup and can talk to your cluster.**

Lets test that our kubectl can talk to the cluster:

```sh
$ kubectl get nodes
NAME                               LABELS                                                    STATUS
gke-cluster-1-01678227-node-79jo   kubernetes.io/hostname=gke-cluster-1-01678227-node-79jo   Ready
```

Next, let's setup some variables, and create a local folder that will hold generated configuration files.

```sh
$ cd openshift-origin-kubernetes-example
$ export BASE=${PWD}
$ export BASE_CONFIG=${BASE}/config
$ mkdir ${BASE_CONFIG}
```

### Step 1: Create an External Load Balancer to Route Traffic to OpenShift

An external load balancer is needed to route traffic to our OpenShift master service that will run as a pod on your
Kubernetes cluster.


```sh
$ kubectl create -f $BASE/openshift-service.yaml
```

### Step 2: Generate configuration file for your OpenShift master pod

The OpenShift master requires a configuration file as input to know how to bootstrap the system.

In order to build this configuration file, we need to know the public IP address of our external load balancer in order to
build default certificates.

Grab the public IP address of the service we previously created.

```sh
$ export PUBLIC_IP=$(kubectl get services openshift --template="{{ index .status.loadBalancer.ingress 0 \"ip\" }}")
$ echo "PUBLIC IP: ${PUBLIC_IP}"
```

Ensure you have a valid PUBLIC_IP address before continuing in the example, you might need to wait 60 seconds in order for it to be setup.

We now need to run a command on your host to generate a proper OpenShift configuration.  To do this, we will volume mount our configuration directory and the directory (~/.kube/config) that holds your Kubernetes config file.

```sh
$ docker run --privileged -e KUBECONFIG=/kubeconfig -v ${HOME}/.kube/config:/kubeconfig -v ${BASE_CONFIG}:/config openshift/origin:v1.0.3 start master --write-config=/config --master=https://localhost:8443 --public-master=https://${PUBLIC_IP}:8443
```

You should now see a number of certificates minted in your configuration directory, as well as a master-config.yaml file that tells the OpenShift master how to execute.  In the next step, we will bundle this into a Kubernetes Secret that our OpenShift master pod will consume.

### Step 4: Bundle the configuration into a Secret

We now need to bundle the contents of our configuration into a secret for use by our OpenShift master pod.

OpenShift includes an experimental command to make this easier.

First, update the ownership for the files previously generated:

```
$ sudo -E chown ${USER} -R ${BASE_CONFIG}
```

Then run the following command to collapse them into a Kubernetes secret.

```sh
$ docker run -i -t --privileged -e KUBECONFIG=/kubeconfig -v ${HOME}/.kube/config:/kubeconfig -v ${BASE_CONFIG}:/config openshift/origin:v1.0.3 cli secrets new openshift-config /config -o json &> ${BASE}/secret.json
```

Now, lets create the secret in your Kubernetes cluster.

```sh
$ kubectl create -f ${BASE}/secret.json
```

**NOTE: This secret is secret and should not be shared with untrusted parties.**

### Step 5: Deploy OpenShift Master

We are now ready to deploy OpenShift.

We will deploy a pod that runs the OpenShift master.  The OpenShift master will delegate to the underlying Kubernetes
system to manage Kubernetes specific resources.  For the sake of simplicity, the OpenShift master will run with an embedded etcd to hold OpenShift specific content.  **Note if the OpenShift master fails the etcd content will be lost, this is because etcd is using an ephemeral volume for now.**

```sh
$ kubectl create -f ${BASE}/openshift-controller.yaml
```

You should now get a pod provisioned whose name begins with openshift.

```sh
$ kubectl get pods | grep openshift
$ kubectl logs openshift-3a1dt origin
I0727 22:11:44.720769       1 start_master.go:307] Starting an OpenShift master, reachable at 0.0.0.0:8443 (etcd: [https://localhost:4001])
I0727 22:11:44.720884       1 start_master.go:308] OpenShift master public address is https://130.211.171.209:8443
```

Depending upon your cloud provider, you may need to open up an external firewall rule for tcp:8443.  For GCE, you can run the following (if you are using Google Container Engine this should already be done for you):

```sh
gcloud compute --project "your-project" firewall-rules create "origin" --allow tcp:8443 --network "your-network" --source-ranges "0.0.0.0/0"
```

Consult your cloud provider's documentation for more information.

### Step 6: Test it out

Open a browser and visit the OpenShift master public address reported in your log, any username and password will work as we haven't configured authentication yet.

You can use the CLI commands by running the following:

```sh
$ docker run --privileged --entrypoint="/usr/bin/bash" -it -e KUBECONFIG=/kubeconfig -v ${HOME}/.kube/config:/kubeconfig openshift/origin:v1.0.3
$ oc help
$ oc get pods
```

Or if you have the OpenShift CLI installed on your local machine you can can skip the docker run command above and just do:

```sh
$ oc help
$ oc get pods
```
