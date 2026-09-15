ARG K3S_VERSION=v1.36.0-k3s1
ARG NVIDIA_TOOLKIT_IMAGE=nvcr.io/nvidia/k8s/container-toolkit:v1.17.8-ubuntu20.04

FROM alpine:3.22 AS tools
RUN apk add --no-cache patchelf

FROM ${NVIDIA_TOOLKIT_IMAGE} AS nvidia-toolkit

FROM rancher/k3s:${K3S_VERSION}

# NVIDIA CDI hooks need nvidia-ctk and ldconfig in the outer K3s container.
COPY --from=nvidia-toolkit /usr/bin/nvidia-ctk /usr/libexec/nvidia-ctk
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/ld-2.31.so /lib/x86_64-linux-gnu/ld-2.31.so
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libc-2.31.so /lib/x86_64-linux-gnu/libc-2.31.so
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libdl-2.31.so /lib/x86_64-linux-gnu/libdl-2.31.so
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libpthread-2.31.so /lib/x86_64-linux-gnu/libpthread-2.31.so
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libresolv-2.31.so /lib/x86_64-linux-gnu/libresolv-2.31.so
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libc.so.6 /lib/x86_64-linux-gnu/libc.so.6
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libdl.so.2 /lib/x86_64-linux-gnu/libdl.so.2
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libpthread.so.0 /lib/x86_64-linux-gnu/libpthread.so.0
COPY --from=nvidia-toolkit /lib/x86_64-linux-gnu/libresolv.so.2 /lib/x86_64-linux-gnu/libresolv.so.2
COPY --from=nvidia-toolkit /lib64/ld-linux-x86-64.so.2 /lib64/ld-linux-x86-64.so.2
COPY --from=nvidia-toolkit /sbin/ldconfig /sbin/ldconfig
COPY --from=nvidia-toolkit /sbin/ldconfig.real /sbin/ldconfig.real
COPY --from=tools /usr/bin/patchelf /usr/local/bin/patchelf
COPY --from=tools /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
COPY --from=tools /usr/lib/libstdc++.so.6 /usr/lib/libstdc++.so.6
COPY --from=tools /usr/lib/libgcc_s.so.1 /usr/lib/libgcc_s.so.1

COPY entrypoint.sh /usr/local/bin/k3s-gpu-entrypoint
COPY nvidia-ctk-wrapper.sh /usr/bin/nvidia-ctk
COPY manifests/nvidia-device-plugin.yaml /usr/local/share/k3s/nvidia-device-plugin.yaml

ARG K3S_VERSION
LABEL org.opencontainers.image.title="containerized-k3s-gpu-node" \
      org.opencontainers.image.description="K3s with nested NVIDIA CDI support" \
      org.opencontainers.image.version="${K3S_VERSION}" \
      org.opencontainers.image.licenses="Apache-2.0"

ENTRYPOINT ["/usr/local/bin/k3s-gpu-entrypoint"]
