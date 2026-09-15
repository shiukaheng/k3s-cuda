# K3s GPU Node Image

One Docker container becomes a standalone K3s node with NVIDIA GPU support.

Kubernetes workloads only need:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

No workload `hostPath`, `/nix/store`, `/usr/local/nvidia`, or `RuntimeClass` is required.

## Requirements

- x86_64 Linux
- NVIDIA driver
- Docker with NVIDIA Container Toolkit integration
- Docker Compose

This must work first:

```bash
docker run --rm --gpus all \
  nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

## Start

```bash
docker compose build
docker compose up -d
```

Wait for the node and GPU plugin:

```bash
docker compose logs -f k3s
```

Copy the kubeconfig:

```bash
docker compose cp k3s:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl get nodes
```

Test the GPU:

```bash
kubectl apply -f manifests/gpu-test-portable.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded \
  pod/k3s-gpu-test-portable --timeout=180s
kubectl logs k3s-gpu-test-portable
```

Stop while keeping the cluster:

```bash
docker compose down
```

Delete the cluster and its volumes:

```bash
docker compose down -v
```

## Use A Published Image

Set the image and skip the build:

```bash
K3S_IMAGE=ghcr.io/<owner>/<repository>:<tag> \
  docker compose up -d --no-build
```

The GitHub workflow publishes `linux/amd64` images for tags matching `v*`.

## Relationship To Upstream K3s

The image is based directly on `rancher/k3s:v1.36.0-k3s1`. It does not rebuild or replace K3s or its embedded containerd. It adds only the components required to pass Docker-provided NVIDIA devices into nested Kubernetes workloads:

- NVIDIA `nvidia-ctk`, `ldconfig`, and their minimal runtime libraries for CDI injection
- NVIDIA device plugin v0.17.1, configured with `cdi-cri` and installed automatically in server mode
- a small entrypoint that exposes Docker-injected driver files at stable paths
- `patchelf` for the conditional NixOS compatibility fix described below

The image does not contain an NVIDIA driver, CUDA toolkit, or workload image. Docker supplies the host's matching driver and devices through `gpus: all`.

```text
host NVIDIA driver -> Docker GPU injection -> K3s container
  -> NVIDIA device plugin/CDI -> K3s containerd -> GPU workload
```

The device plugin advertises `nvidia.com/gpu` and generates the CDI specification. Embedded containerd then injects the allocated devices, driver libraries, and utilities into the workload. This is why workloads need only the GPU resource limit shown above.

K3s data uses a Docker named volume, so embedded containerd can use its default `overlayfs` snapshotter directly on the host backing filesystem. This preserves image-layer sharing and avoids inefficient full-filesystem copies from the `native` snapshotter.

## Why `patchelf` Exists

NixOS's injected `nvidia-smi` has an absolute ELF interpreter under `/nix/store`. A normal Ubuntu CUDA pod does not have that path.

The entrypoint copies `nvidia-smi` inside the K3s container and changes the copy only when its interpreter starts with `/nix/store/`. It never modifies the host. On Ubuntu, Debian, and other conventional hosts, no interpreter change is made.

This is limited to making the `nvidia-smi` utility portable. Driver libraries and devices still come from NVIDIA's normal Docker injection.

## Files

```text
Dockerfile                         custom K3s image
compose.yaml                       complete deployment
entrypoint.sh                      driver view and plugin installation
nvidia-ctk-wrapper.sh              isolates toolkit glibc on NixOS
manifests/nvidia-device-plugin.yaml
manifests/gpu-test-portable.yaml
```

## Scope

- Validated on NixOS, RTX 4090, driver 595.99.02
- Designed for x86_64 Linux hosts where the Docker prerequisite passes
- Ubuntu and Debian still need physical cross-host validation
- Standalone single-node K3s server only
- Privileged container; not a security boundary
