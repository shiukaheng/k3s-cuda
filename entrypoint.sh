#!/bin/sh
set -eu

root=/run/k3s-nvidia/driver
mkdir -p "$root/lib64" "$root/usr/bin"

for candidate in /usr/local/nvidia/lib64 /usr/local/nvidia/lib /usr/lib/x86_64-linux-gnu /usr/lib64 /lib/x86_64-linux-gnu /lib64; do
  if [ -e "$candidate/libcuda.so.1" ] && [ -e "$candidate/libnvidia-ml.so.1" ]; then
    mount --bind "$candidate" "$root/lib64"
    break
  fi
done
[ -e "$root/lib64/libcuda.so.1" ] || { printf 'Docker did not inject NVIDIA driver libraries\n' >&2; exit 1; }

cp "$(command -v nvidia-smi)" "$root/usr/bin/nvidia-smi"
case "$(patchelf --print-interpreter "$root/usr/bin/nvidia-smi")" in
  /nix/store/*) patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$root/usr/bin/nvidia-smi" ;;
esac

if [ "${1:-}" = server ]; then
  mkdir -p /var/lib/rancher/k3s/server/manifests
  cp /usr/local/share/k3s/nvidia-device-plugin.yaml /var/lib/rancher/k3s/server/manifests/
fi

exec /bin/k3s "$@"
