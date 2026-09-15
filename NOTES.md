# Experiment Notes

## Minimal image iteration

The documented K3s NVIDIA runtime approach was tested without `patchelf`. K3s correctly discovered the bundled `nvidia-container-runtime`, but the physical NixOS `nvidia-smi` retained its `/nix/store/.../ld-linux` interpreter when injected into the Ubuntu pod. NVIDIA's runtime does not rewrite ELF interpreters, so the pod failed with `exec /usr/bin/nvidia-smi: no such file or directory`.

The final image therefore keeps the proven CDI path and one conditional compatibility operation: copy injected `nvidia-smi` inside the outer container and use `patchelf` only when its interpreter is a Nix-store path. No host file is changed, and conventional Linux binaries are left untouched.

Deployment was reduced to `compose.yaml`; lifecycle and test orchestration scripts were removed.

## Portable result

Final classification: `PORTABLE PASS`.

The successful path uses Kubernetes `cdi-cri`, the NVIDIA device plugin's CDI generator, and K3s embedded containerd's default CDI support. The clean workload has no volumes. The CDI spec is generated in `/var/run/cdi` inside the K3s node, and every driver-library source resolves through `/run/k3s-nvidia/driver` in that same outer-container namespace.

## Portable attempt 4

Result -> PASS. After adding the toolkit's `ldconfig` to the K3s image, `k3s-gpu-test-portable` completed with exit code 0 and reported the RTX 4090 through driver 595.99.02. The previous explicit-mount fallback also completed under the new CDI plugin configuration.

## Portable attempt 3

Failure -> the included `nvidia-ctk` hook reached `update-ldcache`, but the minimal K3s image had no `/sbin/ldconfig`.

Change -> include the toolkit image's `ldconfig` and `ldconfig.real`. These are runtime plumbing, not driver files.

## Portable attempt 2

Failure -> plugin-generated CDI had correct normalized library and device sources, but runc could not execute `/usr/bin/nvidia-ctk`. After adding the Ubuntu-built binary, Docker's injected NixOS loader cache caused it to select Nix glibc and fail with a GLIBC mismatch.

Change -> include NVIDIA Container Toolkit 1.17.8 and its private Ubuntu glibc in the image. `/usr/bin/nvidia-ctk` is a static-shell wrapper that pins `LD_LIBRARY_PATH` before executing `/usr/libexec/nvidia-ctk`.

## Portable attempt 1

Failure -> CDI mode initially classified the plugin as non-NVML because its process loader could not see the normalized driver tree. The first generated spec also transformed `/dev` paths under the driver root.

Change -> expose normalized libraries at the plugin image's `/usr/local/nvidia/lib64`, set discovery root to `/driver-root`, target driver root to `/run/k3s-nvidia/driver`, and target device root to `/`.

This produced correct CDI sources from embedded containerd's perspective:

```text
/run/k3s-nvidia/driver/lib64/...
/run/k3s-nvidia/driver/usr/bin/nvidia-smi
/dev/nvidia0
/dev/nvidiactl
```

## Upstream findings

- CDI `hostPath` is relative to the consuming runtime's host namespace: <https://github.com/cncf-tags/container-device-interface/blob/main/SPEC.md#oci-edits>
- NVIDIA CDI generation and standard `/etc/cdi`, `/var/run/cdi` locations: <https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html>
- `nvidia-ctk cdi generate` driver-root discovery and `cdi transform root` are supported, but a root transform is valid only when the transformed source exists in the consumer namespace: <https://github.com/NVIDIA/nvidia-container-toolkit/tree/main/cmd/nvidia-ctk/cdi>
- K3s containerd configuration and NVIDIA runtime discovery: <https://docs.k3s.io/advanced#configuring-containerd>
- Device plugin v0.17.1 supports `envvar`, `volume-mounts`, `cdi-annotations`, and `cdi-cri`: <https://github.com/NVIDIA/k8s-device-plugin/blob/v0.17.1/README.md#device-list-strategy>
- `cdi-cri` is appropriate because CDI devices in the device-plugin API are GA in Kubernetes 1.31 and K3s is v1.36. Device plugin v0.17.1 writes its own matching CDI spec when a CDI strategy is enabled.
- `pass-device-specs` is not used in CDI-only mode; it is primarily for CPU Manager compatibility.

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

Change -> mount Docker-injected `/usr/local/nvidia` into the plugin, set `--container-driver-root=/usr/local/nvidia`, and make a test-local `cdi/` directory writable by both the plugin and inner containerd. The test orchestration copied the host's static NVIDIA CDI spec into that directory on each fresh run.

Result -> pending.
