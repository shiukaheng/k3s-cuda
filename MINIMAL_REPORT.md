# Containerized K3s GPU: Validated Minimal Report

## Result

**PASS:** a pod run by K3s's embedded containerd requested `nvidia.com/gpu: 1` and ran `nvidia-smi` against the physical host GPU.

Validated path:

```text
host NVIDIA driver -> Docker --gpus all -> privileged K3s container
-> K3s embedded containerd -> Kubernetes GPU pod
```

## Tested versions

| Component | Value |
| --- | --- |
| K3s image | `rancher/k3s:v1.36.0-k3s1` |
| Embedded containerd | `2.2.3-k3s1` |
| NVIDIA device plugin | `v0.17.1` |
| CUDA test image | `nvidia/cuda:12.8.1-base-ubuntu24.04` |

## Host prerequisites

These are required on every host:

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

Do not proceed if the second command fails. K3s cannot repair a missing Docker/NVIDIA integration.

The tested Docker command needs a privileged container because K3s runs kubelet, CNI, and containerd inside Docker:

```bash
docker run -d --name k3s-gpu-test-server --hostname k3s-gpu-test-server \
  --privileged --gpus all -p 127.0.0.1:6443:6443 \
  -v "$PWD/state:/var/lib/rancher/k3s" \
  k3s-gpu-test:v1.36.0-k3s1 server \
  --snapshotter native --disable traefik --disable servicelb
```

`--snapshotter native` is required when the K3s data directory is on Docker overlayfs. Nested overlayfs failed on this host.

## GPU configuration

Deploy NVIDIA's official device plugin with `pass-device-specs` enabled. This makes kubelet pass allocated GPU device nodes to K3s's embedded containerd:

```yaml
args:
  - --pass-device-specs=true
securityContext:
  privileged: true
```

Verify both values after the plugin is running:

```bash
kubectl get node -o jsonpath='{.status.capacity.nvidia\.com/gpu}{" "}{.status.allocatable.nvidia\.com/gpu}{"\n"}'
# Expected for one GPU: 1 1
```

GPU workloads request one GPU conventionally:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

## NixOS-specific details

The validated workload manifest additionally mounts the NVIDIA libraries and `nvidia-smi` that Docker injected into the outer K3s container:

```yaml
hostPath: { path: /usr/local/nvidia }
hostPath: { path: /usr/bin/nvidia-smi, type: File }
hostPath: { path: /nix/store }
```

The `/nix/store` mount is **specific to this NixOS setup**. The host-injected `nvidia-smi` is dynamically linked to Nix-store glibc and driver paths. On conventional Linux distributions, mount the distribution's driver-library directory and `nvidia-smi` path instead, or install/configure an NVIDIA container runtime inside the K3s image.

## CDI finding

Docker on this NixOS host exposes CDI devices, but the NVIDIA device plugin's generated allocation CDI specification resolved libraries from `/lib64`; Docker injected them into the outer K3s container at `/usr/local/nvidia/lib64`. The CDI attempt therefore failed before process start. Direct CRI device specs plus explicit read-only driver mounts succeeded.

This proves the nested K3s architecture works, but the exact driver mounts are host-integration-dependent. See `README.md`, `NOTES.md`, and `logs/test-results.md` for the complete reproducible experiment and recorded output.
