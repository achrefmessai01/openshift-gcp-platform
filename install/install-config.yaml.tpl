# OpenShift installer configuration (IPI on GCP, existing VPC created by terraform/).
# Rendered by install/render-install-config.sh with envsubst; do not fill by hand.
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
controlPlane:
  name: master
  replicas: 3
  hyperthreading: Enabled
  architecture: amd64
  platform:
    gcp:
      type: ${CONTROL_PLANE_TYPE}
      osDisk:
        diskType: pd-ssd
        diskSizeGB: 128
compute:
  - name: worker
    replicas: ${WORKER_REPLICAS}
    hyperthreading: Enabled
    architecture: amd64
    platform:
      gcp:
        type: ${WORKER_TYPE}
        osDisk:
          diskType: pd-ssd
          diskSizeGB: 128
networking:
  networkType: OVNKubernetes
  clusterNetwork:
    - cidr: 10.128.0.0/14
      hostPrefix: 23
  machineNetwork:
    - cidr: ${MACHINE_CIDR}
  serviceNetwork:
    - 172.30.0.0/16
platform:
  gcp:
    projectID: ${PROJECT_ID}
    region: ${REGION}
    network: ${NETWORK}
    controlPlaneSubnet: ${CONTROL_PLANE_SUBNET}
    computeSubnet: ${COMPUTE_SUBNET}
    userLabels:
      - key: owner
        value: platform-team
      - key: managed-by
        value: openshift-install
publish: ${PUBLISH}
pullSecret: '${PULL_SECRET}'
sshKey: '${SSH_PUBLIC_KEY}'
