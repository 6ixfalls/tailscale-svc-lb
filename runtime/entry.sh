#!/bin/bash

TS_USERSPACE=false

# Set to 'true' to skip leadership election. Only use when testing against one node
#   This is useful on non x86_64 architectures, as the leader-elector image is only provided for that arch
DEBUG_SKIP_LEADER="${DEBUG_SKIP_LEADER:-false}"

set -e

if [[ "${DEBUG_SKIP_LEADER}" == "true" ]]; then
  echo "CAUTION: Skipping leader election due to DEBUG_SKIP_LEADER==true."
else
  echo "Waiting for leader election..."
  LEADER=false
  while :; do
    CURRENT_LEADER=$(curl http://127.0.0.1:4040 -s -m 2 | jq -r ".name")
    if [[ "${CURRENT_LEADER}" == "$(hostname)" ]]; then
      echo "I am the leader."
      break
    fi
    sleep 1
  done
fi

echo "Running tailscale entrypoint"
/usr/local/bin/containerboot &
PID=$!

echo "Waiting for tailscale to be Running"
while :; do
  sleep 2
  TAILSCALE_BACKEND_STATE="$(tailscale status -json | grep -oP '"BackendState": "\K[^"]*')"
  if [ "${TAILSCALE_BACKEND_STATE}" == "Running" ]; then
    echo "Tailscale is up"
    break
  fi
done

TS_IP=$(tailscale --socket=/tmp/tailscaled.sock ip -4)
TS_IP_B64=$(echo -n "${TS_IP}" | base64 -w 0)

# Technically can get the service ClusterIP through the <svc-name>_SERVICE_HOST variable
# but no idea how to do that in a sane way in pure Bash, so let's just get it from kube-dns
PROXY_NAMESPACE=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
echo "Trying to get the service ClusterIP..."
SVC_IP_RETRIEVED=false
while [[ "${SVC_IP_RETRIEVED}" == "false" ]]; do
  SVC_IP=$(getent hosts ${SVC_NAME}.${SVC_NAMESPACE}.svc | cut -d" " -f1)
  if [[ -n "${SVC_IP}" ]]; then
    SVC_IP_RETRIEVED=true
  else
    sleep 1
  fi
done

echo "Adding iptables rule for DNAT"
iptables -t nat -I PREROUTING -d "${TS_IP}" -j DNAT --to-destination "${SVC_IP}"
iptables -t nat -A POSTROUTING -j MASQUERADE

PRIMARY_NETWORK_INTERFACE=$(route | grep '^default' | grep -o '[^ ]*$')
iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -o ${PRIMARY_NETWORK_INTERFACE} -j TCPMSS --set-mss 1240   

echo "Updating secret with Tailscale IP"
# patch secret with the tailscale ipv4 address
kubectl patch secret "${TS_KUBE_SECRET}" --namespace "${PROXY_NAMESPACE}" --type=json --patch="[{\"op\":\"replace\",\"path\":\"/data/ts-ip\",\"value\":\"${TS_IP_B64}\"}]"

wait ${PID}