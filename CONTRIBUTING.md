# Contributing

Changes should preserve the core architecture: Docker on the physical host, one privileged containerized K3s node, and GPU workloads under K3s's embedded containerd. Do not convert the project to host-installed K3s.

Before opening a pull request:

```bash
sh -n entrypoint.sh nvidia-ctk-wrapper.sh
docker compose build
docker compose down -v
docker compose up -d
docker compose cp k3s:/etc/rancher/k3s/k3s.yaml ./kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl apply -f manifests/gpu-test-portable.yaml
git diff --check
```

GPU validation requires a Linux NVIDIA host. GitHub-hosted CI validates syntax and image construction but cannot execute the GPU smoke test.

Keep `manifests/gpu-test-portable.yaml` free of `hostPath` volumes and host-specific NVIDIA paths. Preserve the known-good fallback manifests when changing the portable path.

Bug reports should include the host distribution and architecture, Docker version, NVIDIA driver and toolkit versions, GPU model, `docker compose logs` output, and pod events. Do not include kubeconfig credentials or K3s tokens.
