#!/bin/bash

export BASE=$(pwd)
export BASE_CONFIG=${BASE}/config
rm -fr ${BASE_CONFIG}
kubectl delete secrets openshift-config
kubectl stop rc openshift
kubectl delete rc openshift
kubectl delete services openshift
