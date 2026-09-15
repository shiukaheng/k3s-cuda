#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
name="k3s-gpu-test-server"
image="k3s-gpu-test:v1.36.0-k3s1"

if [[ ! -f /run/cdi/nvidia-container-toolkit.json ]]; then
  printf 'Missing host CDI specification: /run/cdi/nvidia-container-toolkit.json\n' >&2
  exit 1
fi

docker rm -f "$name" >/dev/null 2>&1 || true
mkdir -p "$root/state"
mkdir -p "$root/cdi"
# K3s writes state as root inside its privileged container. Reset only this
# bind mount through Docker so subsequent unprivileged reruns do not need sudo.
docker run --rm --volume "$root/state:/state" busybox:1.37.0 sh -c 'rm -rf /state/*'
docker run --rm --volume "$root/cdi:/cdi" busybox:1.37.0 sh -c 'rm -rf /cdi/*'
cp /run/cdi/nvidia-container-toolkit.json "$root/cdi/nvidia-container-toolkit.json"
rm -f "$root/kubeconfig.yaml"

# --privileged permits K3s's nested containerd, kubelet, CNI and mounts.
# --gpus all injects NVIDIA devices and driver libraries into the outer K3s container.
# The CDI mount lets the inner containerd resolve NVIDIA devices selected by the plugin.
docker run --detach \
  --name "$name" \
  --hostname "$name" \
  --privileged \
  --gpus all \
  --network bridge \
  --publish 127.0.0.1:6443:6443 \
  --volume "$root/state:/var/lib/rancher/k3s" \
  --volume "$root/cdi:/var/run/cdi" \
  "$image" server \
  --snapshotter native \
  --disable traefik \
  --disable servicelb \
  --write-kubeconfig-mode 644

for _ in $(seq 1 90); do
  if docker exec "$name" kubectl get node --no-headers 2>/dev/null | grep -q ' Ready '; then
    docker cp "$name:/etc/rancher/k3s/k3s.yaml" "$root/kubeconfig.yaml"
    # The container's loopback endpoint is not reachable from the host.
    perl -0pi -e 's#server: https://127\.0\.0\.1:6443#server: https://127.0.0.1:6443#' "$root/kubeconfig.yaml"
    exit 0
  fi
  sleep 2
done

docker logs "$name" >"$root/logs/k3s-startup.log" 2>&1 || true
printf 'K3s node did not become Ready; see logs/k3s-startup.log\n' >&2
exit 1
