#!/bin/sh
set -eu

kubectl() {
  docker compose exec -T k3s k3s kubectl "$@"
}

cleanup() {
  kubectl delete daemonset k3s-network-test --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

kubectl apply -f - < manifests/network-test.yaml
kubectl rollout status daemonset/k3s-network-test --timeout=180s

pods=$(kubectl get pods -l app=k3s-network-test \
  -o custom-columns=NAME:.metadata.name,IP:.status.podIP --no-headers)
count=$(printf '%s\n' "$pods" | wc -l)
[ "$count" -gt 1 ] || { printf 'At least two Ready nodes are required.\n' >&2; exit 1; }

printf '%s\n' "$pods" | while read -r source source_ip; do
  printf '%s\n' "$pods" | while read -r destination destination_ip; do
    [ "$source" = "$destination" ] && continue
    kubectl exec "$source" -- ping -c 1 -W 3 "$destination_ip" >/dev/null
    printf '%s -> %s: pass\n' "$source_ip" "$destination_ip"
  done
done
