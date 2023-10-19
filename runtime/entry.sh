#!/bin/bash

export TS_USERSPACE=false
export TS_ACCEPT_DNS=false

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

printenv | grep "TS_"

echo "Running tailscale entrypoint"
/usr/local/bin/containerboot &
PID=$!

# https://github.com/tailscale/tailscale/blob/3f27087e9d139e4d69ca9435fa333702de802bf2/cmd/containerboot/main.go#L545
UP_ARGS="--accept-dns=${TS_ACCEPT_DNS}"
if [[ ! -z "${TS_AUTH_KEY}" ]]; then
  UP_ARGS="--authkey=${TS_AUTH_KEY} ${UP_ARGS}"
fi
if [[ ! -z "${TS_ROUTES}" ]]; then
  UP_ARGS="--advertise-routes=${TS_ROUTES} ${UP_ARGS}"
fi
if [[ ! -z "${TS_HOSTNAME}" ]]; then
  UP_ARGS="--hostname=${TS_HOSTNAME} ${UP_ARGS}"
fi
if [[ ! -z "${TS_EXTRA_ARGS}" ]]; then
  UP_ARGS="${UP_ARGS} ${TS_EXTRA_ARGS:-}"
fi

echo "Waiting for tailscale to be Running"
while :; do
  sleep 2
  TAILSCALE_BACKEND_STATE="$(tailscale --socket=/tmp/tailscaled.sock status -json | grep -o '"BackendState": "[^"]*"' | cut -d '"' -f 4)"
  if [ "${TAILSCALE_BACKEND_STATE}" == "Running" ]; then
    echo "Tailscale is up"
    break
  elif [ "${TAILSCALE_BACKEND_STATE}" == "Stopped" ]; then
    echo "Starting tailscale"
    tailscale --socket=/tmp/tailscaled.sock up ${UP_ARGS} || true
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
