# Experiment Notes

## Attempt 1

Initial build failure -> the current minimal K3s image has no package manager, so it cannot install `nvidia-container-toolkit` with `apk`.

Cause -> this image is not Alpine despite its small filesystem.

Change -> use K3s's bundled CDI-capable containerd directly. Docker's existing NVIDIA integration supplies device nodes, driver libraries, and the CDI hook binary to the outer K3s container. No runtime package is needed in the inner image.

Revised planned configuration: K3s v1.36.0+k3s1, host `/run/cdi/nvidia-container-toolkit.json` mounted read-only, NVIDIA device plugin v0.17.1 using `cdi-annotations`. Its pod mounts the outer container's injected NVIDIA library directory and `/dev` to initialize NVML.

Reasoning: Docker has native CDI support and the host generates `/run/cdi/nvidia-container-toolkit.json`. Docker's outer `--gpus all` injection makes NVIDIA device nodes and matching driver libraries available to the K3s container. The mounted CDI specification lets K3s's inner containerd resolve the GPU device selected by the device plugin.

## Attempt 2

Failure -> nested K3s did not become Ready. Its embedded containerd rejected the default `overlayfs` snapshotter because the K3s data directory is itself on Docker overlayfs (`failed to mount overlay ... invalid argument`).

Change -> start K3s with `--snapshotter native`, the K3s-reported compatible non-overlay snapshotter.

Result -> pending.

## Attempt 7

Result from attempt 6 -> PASS. Eight seconds after creation, `k3s-gpu-test-nvidia-smi` was `Completed` with exit code `0`. Its `kubectl logs` output reported NVIDIA GeForce RTX 4090, driver `595.99.02`, and CUDA `13.2`.

Validated nested path -> host NVIDIA driver -> Docker `--gpus all` -> privileged K3s container -> K3s embedded containerd -> Kubernetes pod. The official NVIDIA device plugin advertised one physical GPU and passed the allocated device specifications through kubelet to embedded containerd.

## Attempt 6

Result from attempt 5 -> the pod started under embedded containerd, then the NixOS-injected `nvidia-smi` returned `exec ... no such file or directory`: its Nix-store ELF interpreter was absent from the pod.

Change -> mount only the outer K3s container's `/nix/store` view read-only. Docker had already injected the specific NVIDIA and glibc Nix store paths into that outer container; this does not mount the NixOS host root.

Result -> pending.

## Attempt 5

Result from attempt 4 -> the node capacity and allocatable values both became `nvidia.com/gpu: 1`; the one-GPU pod was scheduled and internal containerd created it. It failed before process start because the CUDA base image does not itself ship `nvidia-smi`; Docker ordinarily injects the host executable, but direct device specs only add device nodes.

Change -> explicitly mount Docker-injected `/usr/bin/nvidia-smi` from the outer K3s node into the GPU pod, alongside the injected NVIDIA library tree.

Result -> pending.

## Attempt 4

Result from attempt 3 -> K3s was Ready, the plugin was healthy, and the node advertised `nvidia.com/gpu: 1`. The allocated pod reached internal containerd but failed before execution because the plugin's generated CDI spec requires source libraries at `/lib64`; Docker injects the NixOS driver into the outer minimal K3s image at `/usr/local/nvidia/lib64` instead.

Change -> switch the official device plugin to `--pass-device-specs=true`, its documented direct CRI device-spec mechanism. The GPU pod explicitly mounts the outer K3s node's Docker-injected `/usr/local/nvidia` driver tree. Kubelet passes allocated character devices to embedded containerd; the CUDA image's standard `LD_LIBRARY_PATH` resolves the mounted libraries. This avoids adding a glibc/NVIDIA toolkit stack solely to execute the allocation CDI hooks.

Result -> pending.

## Attempt 3

Result from attempt 2 -> K3s reached Ready with `native`, and the device-plugin pod loaded NVML and identified the RTX 4090. The plugin then failed while generating its allocation CDI specification because it searched its default `/driver-root` and could not find `libcuda.so.595.99.02`.

Change -> mount Docker-injected `/usr/local/nvidia` into the plugin, set `--container-driver-root=/usr/local/nvidia`, and make a test-local `cdi/` directory writable by both the plugin and inner containerd. `run.sh` copies the host's static NVIDIA CDI spec into that directory on each fresh run.

Result -> pending.
