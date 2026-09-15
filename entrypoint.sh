#!/bin/sh
set -eu

role=${K3S_ROLE:-agent}
case "$role" in
  server|agent) ;;
  *) printf 'K3S_ROLE must be server or agent\n' >&2; exit 1 ;;
esac

mkdir -p /run/appliance /var/run/cdi /var/run/tailscale /var/lib/tailscale
printf '%s\n' "$role" > /run/appliance/role

tailscaled_pid=
k3s_pid=
# Invoked indirectly by signal traps.
# shellcheck disable=SC2329
shutdown() {
  trap - TERM INT
  if [ -n "$k3s_pid" ]; then
    kill -TERM "$k3s_pid" 2>/dev/null || true
    wait "$k3s_pid" 2>/dev/null || true
  fi
  if [ -n "$tailscaled_pid" ]; then
    kill -TERM "$tailscaled_pid" 2>/dev/null || true
    wait "$tailscaled_pid" 2>/dev/null || true
  fi
}
trap shutdown TERM INT

state=/var/lib/tailscale/tailscaled.state
had_tailscale_state=false
[ -s "$state" ] && had_tailscale_state=true

tailscaled --state="$state" --socket=/var/run/tailscale/tailscaled.sock &
tailscaled_pid=$!

i=0
until tailscale status --json >/run/appliance/tailscale-status.json 2>/dev/null; do
  kill -0 "$tailscaled_pid" 2>/dev/null || { printf 'tailscaled exited during startup\n' >&2; exit 1; }
  i=$((i + 1))
  [ "$i" -lt 60 ] || { printf 'timed out waiting for tailscaled\n' >&2; exit 1; }
  sleep 1
done

tailscale_up() (
  set -- up --accept-dns=true --reset --timeout=60s
  [ -z "${TS_HOSTNAME:-}" ] || set -- "$@" "--hostname=$TS_HOSTNAME"
  [ -z "${TS_CONTROL_URL:-}" ] || set -- "$@" "--login-server=$TS_CONTROL_URL"
  if [ "$had_tailscale_state" = false ]; then
    [ -n "${TS_AUTHKEY:-}" ] || { printf 'TS_AUTHKEY is required for first startup\n' >&2; exit 1; }
    set -- "$@" "--auth-key=$TS_AUTHKEY"
  fi
  tailscale "$@"
)

if ! grep -q '"BackendState": "Running"' /run/appliance/tailscale-status.json; then
  tailscale_up
fi

tailscale_ip=$(tailscale ip -4)
[ -n "$tailscale_ip" ] || { printf 'Tailscale did not assign an IPv4 address\n' >&2; exit 1; }
printf '%s\n' "$tailscale_ip" > /run/appliance/tailscale-ip

if [ -z "${K3S_NODE_NAME:-}" ]; then
  K3S_NODE_NAME="k3s-$(printf '%s' "$tailscale_ip" | tr . -)"
  export K3S_NODE_NAME
fi
printf '%s\n' "$K3S_NODE_NAME" > /run/appliance/node-name

join_key=${TS_AUTHKEY:-persisted-state}
vpn_auth="name=tailscale,joinKey=$join_key"
if [ -n "${TS_CONTROL_URL:-}" ]; then
  vpn_auth="$vpn_auth,controlServerURL=$TS_CONTROL_URL"
fi
printf '%s\n' "$vpn_auth" > /run/appliance/vpn-auth
chmod 600 /run/appliance/vpn-auth
K3S_VPN_AUTH_FILE=/run/appliance/vpn-auth
export K3S_VPN_AUTH_FILE

gpu_root=/run/k3s-nvidia/driver
gpu_driver_dir=
if command -v nvidia-smi >/dev/null 2>&1; then
  for candidate in /usr/local/nvidia/lib64 /usr/local/nvidia/lib /usr/lib/x86_64-linux-gnu /usr/lib64 /lib/x86_64-linux-gnu /lib64; do
    if [ -e "$candidate/libcuda.so.1" ] && [ -e "$candidate/libnvidia-ml.so.1" ]; then
      gpu_driver_dir=$candidate
      break
    fi
  done
fi

if [ -n "$gpu_driver_dir" ]; then
  mkdir -p "$gpu_root/lib64" "$gpu_root/usr/bin"
  mount --bind "$gpu_driver_dir" "$gpu_root/lib64"
  cp "$(command -v nvidia-smi)" "$gpu_root/usr/bin/nvidia-smi"
  interpreter=$(patchelf --print-interpreter "$gpu_root/usr/bin/nvidia-smi" 2>/dev/null || true)
  case "$interpreter" in
    /nix/store/*) patchelf --set-interpreter /lib64/ld-linux-x86-64.so.2 "$gpu_root/usr/bin/nvidia-smi" ;;
  esac
  : > /run/appliance/gpu-detected
  printf 'NVIDIA GPU support detected\n'
else
  printf 'NVIDIA GPU support not detected; starting CPU node\n'
fi

if [ "$role" = server ]; then
  manifest_dir=/var/lib/rancher/k3s/server/manifests
  manifest=$manifest_dir/nvidia-device-plugin.yaml
  mkdir -p "$manifest_dir"
  if ! cmp -s /usr/local/share/k3s/nvidia-device-plugin.yaml "$manifest"; then
    cp /usr/local/share/k3s/nvidia-device-plugin.yaml "$manifest.tmp"
    mv "$manifest.tmp" "$manifest"
  fi
else
  [ -n "${K3S_TOKEN:-}" ] || { printf 'K3S_TOKEN is required for an agent\n' >&2; exit 1; }
  [ -n "${K3S_SERVER:-}" ] || { printf 'K3S_SERVER is required for an agent\n' >&2; exit 1; }
  case "$K3S_SERVER" in
    http://*|https://*) K3S_URL=$K3S_SERVER ;;
    *) K3S_URL="https://$K3S_SERVER:6443" ;;
  esac
  export K3S_URL
  printf '%s\n' "$K3S_URL" > /run/appliance/server
fi

if [ "$role" = server ] && [ -n "${TS_HOSTNAME:-}" ]; then
  /bin/k3s server --tls-san "$TS_HOSTNAME" "$@" &
else
  /bin/k3s "$role" "$@" &
fi
k3s_pid=$!
printf '%s\n' "$k3s_pid" > /run/appliance/k3s.pid

set +e
wait "$k3s_pid"
status=$?
set -e
k3s_pid=
rm -f /run/appliance/k3s.pid
kill -TERM "$tailscaled_pid" 2>/dev/null || true
wait "$tailscaled_pid" 2>/dev/null || true
exit "$status"
