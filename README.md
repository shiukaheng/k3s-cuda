# Containerized K3s GPU experiment

This directory is an isolated, one-node experiment. It does not install K3s on NixOS or alter NixOS, Docker, containerd, firewalls, or host networking.

## Architecture

```
NixOS NVIDIA driver -> Docker CDI/NVIDIA runtime -> privileged K3s container
  -> K3s embedded containerd -> NVIDIA device-plugin -> GPU pod
```

The outer Docker daemon injects NVIDIA device nodes, driver libraries, `nvidia-smi`, and the required Nix-store driver/glibc paths with `--gpus all`. The deployed device plugin uses its supported `pass-device-specs` mode: after scheduling an `nvidia.com/gpu` request, kubelet passes the allocated NVIDIA character devices through K3s's embedded containerd. The workload manifest mounts the matching Docker-injected `/usr/local/nvidia` driver tree, `/usr/bin/nvidia-smi`, and only the outer container's injected `/nix/store` view from its K3s node. This avoids injecting a second NVIDIA runtime into the minimal K3s image. K3s v1.36's CDI-capable containerd was also tested; the failed NixOS CDI path experiment is recorded in `NOTES.md`.

## Prerequisites

- NixOS host NVIDIA driver with `nvidia-smi` working.
- Docker with NVIDIA GPU support: `docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi`.
- Host NVIDIA CDI specification at `/run/cdi/nvidia-container-toolkit.json`.

## Commands

Build: `./build.sh`

Run K3s: `./run.sh`

Use the generated kubeconfig: `export KUBECONFIG="$PWD/kubeconfig.yaml"`

Deploy the pinned NVIDIA device plugin: `kubectl apply -f manifests/nvidia-device-plugin.yaml`

Wait for it: `kubectl -n kube-system rollout status daemonset/nvidia-device-plugin-daemonset --timeout=180s`

Inspect capacity: `kubectl get nodes && kubectl describe node`

Run the workload: `kubectl apply -f manifests/gpu-test.yaml && kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/k3s-gpu-test-nvidia-smi --timeout=180s && kubectl logs k3s-gpu-test-nvidia-smi`

Cleanup only this experiment: `./cleanup.sh`; include `--image` to also remove the local image.

The final recorded evidence is in `logs/test-results.md`.

## Container options

- `--privileged` is needed for the nested K3s kubelet, embedded containerd, CNI and mount operations.
- `--gpus all` is required to inject physical NVIDIA devices and host driver libraries into the outer K3s container.
- The test-local `cdi/` mount keeps the host CDI specification available for inspection without modifying the host CDI directory. The validated path uses direct CRI device specs because of a NixOS library-path mismatch in the device plugin's generated CDI spec.
- The bind-mounted `state/` keeps all K3s mutable state in this experiment directory and is removed by `run.sh` before a fresh run.
- `--snapshotter native` is necessary because K3s data lives on Docker overlayfs, which cannot host a nested overlayfs snapshotter. It trades image-layer efficiency for compatibility.

## Scope and caveats

This is intentionally a privileged, single-node development experiment. Nested container runtimes and CDI bind mounts are not a production isolation boundary. See `NOTES.md` and `logs/` for actual run evidence and failures.
