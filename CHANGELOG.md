# Changelog

All notable changes will be documented in this file.

## Unreleased

- Package K3s v1.36.0 as a privileged Docker GPU node image.
- Normalize Docker-injected NVIDIA userspace files inside the node container.
- Use NVIDIA device plugin v0.17.1 with the `cdi-cri` allocation strategy.
- Auto-deploy the pinned device plugin in K3s server mode.
- Run ordinary CUDA workloads with only an `nvidia.com/gpu` resource limit.
- Preserve the previous explicit NixOS mount path as a diagnostic fallback.
- Add a minimal Docker Compose deployment and GHCR publishing workflow.
