# K3s With NVIDIA Support

This is a drop-in derivative of the official `rancher/k3s` image that adds NVIDIA GPU support. It keeps the upstream K3s binary, embedded containerd, defaults, commands, flags, and environment variables unchanged.

Use it like `rancher/k3s`, with one additional Docker option:

```text
--gpus all
```

GPU workloads then need only:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

No workload `hostPath`, `/nix/store`, `/usr/local/nvidia`, or `RuntimeClass` is required.

## What The Image Changes

The image is based directly on `rancher/k3s:v1.36.0-k3s1`. It does not rebuild K3s, replace embedded containerd, or change K3s configuration.

It adds only:

- NVIDIA `nvidia-ctk`, `ldconfig`, and their minimal runtime libraries for CDI injection
- NVIDIA device plugin v0.17.1, configured with `cdi-cri`
- a small entrypoint that prepares Docker-injected driver files, installs the device-plugin manifest on servers, and then runs `/bin/k3s` with the original arguments
- `patchelf` for the conditional NixOS compatibility fix described below

The image does not contain an NVIDIA driver, CUDA toolkit, or workload image. Docker supplies the host's matching driver and devices.

```text
host NVIDIA driver -> Docker GPU injection -> K3s container
  -> NVIDIA device plugin/CDI -> K3s containerd -> GPU workload
```

## Requirements

- x86_64 Linux
- NVIDIA driver
- Docker with NVIDIA Container Toolkit integration

Confirm Docker GPU injection works first:

```bash
docker run --rm --gpus all \
  nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

## Run A Server

This follows the official K3s Docker example, adding only `--gpus all` and this image name:

```bash
docker build -t k3s-cuda:v1.36.0-k3s1 .

docker run --privileged \
  --gpus all \
  --name k3s-server-1 \
  --hostname k3s-server-1 \
  -p 6443:6443 \
  -d k3s-cuda:v1.36.0-k3s1 \
  server
```

Copy the kubeconfig and test the GPU:

```bash
docker cp k3s-server-1:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl get nodes
kubectl apply -f manifests/gpu-test-portable.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/k3s-gpu-test-portable --timeout=180s
kubectl logs k3s-gpu-test-portable
```

Docker Compose provides the same server with a stable node hostname and named volumes for persistent K3s state:

```bash
docker compose build
docker compose up -d
```

## Join Computers Into A Cluster

Run one container on each physical computer. K3s clustering remains unchanged: start one `server`, then start `agent` containers with the standard `K3S_URL` and `K3S_TOKEN` variables.

Containers on different computers must expose their K3s node networking directly to the LAN. `--network host` is the only deployment difference from the single-container example; it avoids hiding each node and its Flannel interface behind a host-local Docker bridge.

On the server computer:

```bash
docker run --privileged \
  --gpus all \
  --network host \
  --name k3s \
  --hostname "$(hostname)" \
  -v k3s-data:/var/lib/rancher/k3s \
  -v k3s-cni:/var/lib/cni \
  -v k3s-kubelet:/var/lib/kubelet \
  -d k3s-cuda:v1.36.0-k3s1 \
  server

docker exec k3s cat /var/lib/rancher/k3s/server/node-token
```

On each agent computer:

```bash
docker run --privileged \
  --gpus all \
  --network host \
  --name k3s \
  --hostname "$(hostname)" \
  -e K3S_URL=https://SERVER_LAN_IP:6443 \
  -e K3S_TOKEN=SERVER_NODE_TOKEN \
  -v k3s-data:/var/lib/rancher/k3s \
  -v k3s-cni:/var/lib/cni \
  -v k3s-kubelet:/var/lib/kubelet \
  -d k3s-cuda:v1.36.0-k3s1 \
  agent
```

Each computer must have a unique hostname. Standard K3s firewall requirements also apply: TCP 6443 from agents to the server, UDP 8472 between nodes for default Flannel VXLAN, and TCP 10250 between nodes for metrics and kubelet access. Do not expose UDP 8472 to the public internet.

The server installs the NVIDIA device plugin as a DaemonSet, so Kubernetes starts it automatically on every joined GPU node.

## Published Images

The GitHub workflow publishes `linux/amd64` images for tags matching `v*`. To use one, substitute the published image anywhere `k3s-cuda:v1.36.0-k3s1` appears:

```text
ghcr.io/<owner>/<repository>:<tag>
```

## Why `patchelf` Exists

NixOS's injected `nvidia-smi` has an absolute ELF interpreter under `/nix/store`. A normal Ubuntu CUDA pod does not have that path.

The entrypoint copies `nvidia-smi` inside the K3s container and changes the copy only when its interpreter starts with `/nix/store/`. It never modifies the host. On Ubuntu, Debian, and other conventional hosts, no interpreter change is made.

This is limited to making the `nvidia-smi` utility portable. Driver libraries and devices still come from NVIDIA's normal Docker injection.

## Scope

- Validated on NixOS, RTX 4090, driver 595.99.02
- Designed for x86_64 Linux hosts where the Docker prerequisite passes
- Ubuntu and Debian still need physical cross-host validation
- Privileged container; not a security boundary
