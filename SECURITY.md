# Security

This project intentionally runs the K3s node container with Docker `--privileged`. The container can control host devices, mounts, networking, and cgroups and must not be treated as a security boundary.

Use only trusted K3s node images, Kubernetes manifests, and workload images. The Compose file binds the Kubernetes API to loopback. Protect the `k3s-gpu-test-data` volume and `kubeconfig.yaml`; they contain cluster credentials and secrets.

Report security issues privately through the GitHub repository's security advisory feature rather than a public issue. Include affected versions, reproduction steps, and impact. Do not include live credentials.
