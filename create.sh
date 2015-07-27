#!/bin/bash

export BASE=${PWD}
export BASE_CONFIG=${BASE}/config
mkdir ${BASE_CONFIG}
#kubectl config view --output=yaml --flatten=true --minify=true > ${BASE_CONFIG}/kubeconfig
kubectl create -f $BASE/openshift-service.yaml
sleep 60
export PUBLIC_IP=$(kubectl get services openshift --template="{{ index .status.loadBalancer.ingress 0 \"ip\" }}")
echo "PUBLIC IP: ${PUBLIC_IP}"
docker run --privileged -e KUBECONFIG=/kubeconfig -v ${HOME}/.kube/config:/kubeconfig -v ${BASE_CONFIG}:/config openshift/origin:v1.0.3 start master --write-config=/config --master=https://localhost:8443 --public-master=https://${PUBLIC_IP}:8443
#sudo -E chown ${USER} -R ${BASE_CONFIG}
docker run -i -t --privileged -e KUBECONFIG=/kubeconfig -v ${HOME}/.kube/config:/kubeconfig -v ${BASE_CONFIG}:/config openshift/origin:v1.0.3 cli secrets new openshift-config /config -o json &> ${BASE}/secret.json
kubectl create -f ${BASE}/secret.json
kubectl create -f ${BASE}/openshift-controller.yaml
kubectl get pods | grep openshift
