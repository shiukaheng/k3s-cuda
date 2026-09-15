# Test Results

Date: 2026-09-15

Result: `PORTABLE PASS`

## Tested stack

```text
Host: NixOS 26.11
Architecture: x86_64
GPU: NVIDIA GeForce RTX 4090
Driver: 595.99.02
Docker: 29.7.2
K3s: v1.36.0+k3s1
Embedded containerd: 2.2.3-k3s1
NVIDIA device plugin: v0.17.1
NVIDIA CDI hook tooling: v1.17.8
```

## Minimal Compose validation

```text
docker compose build: PASS
docker compose up -d: PASS
Kubernetes node Ready: PASS
NVIDIA device-plugin rollout: PASS
GPU capacity: 1
portable pod phase: Succeeded
portable pod exit code: 0
known-good fallback: PASS
```

The portable pod used `nvidia/cuda:12.8.1-base-ubuntu24.04`, requested `nvidia.com/gpu: 1`, and had no volumes or `RuntimeClass`.

Its output included:

```text
NVIDIA-SMI 595.99.02
NVIDIA GeForce RTX 4090
```

## Interpreter finding

The official NVIDIA runtime path was tested without rewriting `nvidia-smi`. K3s found `nvidia-container-runtime`, but the NixOS-injected binary retained an absolute `/nix/store/.../ld-linux-x86-64.so.2` interpreter and failed inside the Ubuntu pod.

The final entrypoint copies that binary inside the outer node and changes the copy only when the interpreter starts with `/nix/store/`. No physical-host file is modified. This is not used for conventionally packaged `nvidia-smi` binaries.
