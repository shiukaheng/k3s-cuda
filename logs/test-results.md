# Final Test Results

Date: 2026-09-15

## Host prerequisites

- NixOS: `26.11.20260905.c043004 (Zokor)`
- Kernel: `6.18.49`
- GPU: NVIDIA GeForce RTX 4090
- NVIDIA driver: `595.99.02` (CUDA `13.2`)
- Docker client/server: `29.7.2`
- Docker reports native CDI devices: `nvidia.com/gpu=0`, `nvidia.com/gpu=all`
- Outer Docker validation used `nvidia/cuda:12.8.1-base-ubuntu24.04` and returned the RTX 4090 through `nvidia-smi`.

## K3s node

```
NAME                  STATUS   ROLES           VERSION        CONTAINER-RUNTIME
k3s-gpu-test-server   Ready    control-plane   v1.36.0+k3s1   containerd://2.2.3-k3s1
```

Kubernetes node capacity and allocatable GPU values:

```
capacity.nvidia.com/gpu:    1
allocatable.nvidia.com/gpu: 1
```

## GPU workload

The pod requested exactly `nvidia.com/gpu: 1` and was scheduled to `k3s-gpu-test-server`.

```
NAME                      READY   STATUS      IP           NODE
k3s-gpu-test-nvidia-smi   0/1     Completed   10.42.0.10   k3s-gpu-test-server
```

Its terminated container state was `Completed`, exit code `0`.

`kubectl logs k3s-gpu-test-nvidia-smi`:

```
NVIDIA-SMI 595.99.02              Driver Version: 595.99.02      CUDA Version: 13.2
|   0  NVIDIA GeForce RTX 4090        Off |   00000000:01:00.0  On |
```

This `nvidia-smi` execution was inside the Kubernetes pod created by K3s's embedded containerd, not in the outer Docker K3s container.
