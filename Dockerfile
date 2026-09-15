ARG K3S_VERSION=v1.36.0-k3s1
FROM rancher/k3s:${K3S_VERSION}

# K3s v1.36 bundles CDI-capable containerd. NVIDIA's CDI hooks and driver
# libraries are supplied by Docker's outer GPU injection, not copied here.
LABEL org.opencontainers.image.title="k3s-gpu-test" \
      org.opencontainers.image.description="K3s with externally supplied NVIDIA CDI"
