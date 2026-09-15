#!/bin/sh
set -u

if tailscale status --json 2>/dev/null | grep -q '"BackendState": "Running"'; then
  printf 'Tailscale: connected\n'
else
  printf 'Tailscale: disconnected\n'
fi
printf 'Tailscale IP: %s\n\n' "$(cat /run/appliance/tailscale-ip 2>/dev/null || printf unknown)"

role=$(cat /run/appliance/role 2>/dev/null || printf unknown)
node=$(cat /run/appliance/node-name 2>/dev/null || printf unknown)
printf 'K3s role: %s\n' "$role"
if [ "$role" = agent ]; then
  printf 'K3s server: %s\n' "$(cat /run/appliance/server 2>/dev/null || printf unknown)"
fi

if [ "$role" = server ]; then
  kubeconfig=/etc/rancher/k3s/k3s.yaml
else
  kubeconfig=/var/lib/rancher/k3s/agent/kubelet.kubeconfig
fi

ready=$(/bin/k3s kubectl --kubeconfig "$kubeconfig" get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
case "$ready" in
  True) printf 'Kubernetes node: Ready\n' ;;
  False) printf 'Kubernetes node: NotReady\n' ;;
  *) printf 'Kubernetes node: starting or unavailable\n' ;;
esac

if [ -e /run/appliance/gpu-detected ]; then
  printf '\nNVIDIA: detected\n'
else
  printf '\nNVIDIA: not detected\n'
fi
gpu=$(/bin/k3s kubectl --kubeconfig "$kubeconfig" get node "$node" -o 'jsonpath={.status.capacity.nvidia\.com/gpu}' 2>/dev/null || true)
printf 'GPU resources: %s\n' "${gpu:-0}"
