# Portable K3s Node Appliance

Run a self-contained K3s node inside Docker with optional NVIDIA GPU support and Tailscale networking. Add machines to your cluster without installing K3s or Tailscale on the host.

```text
computer appears
      |
docker compose up -d
      v
cluster gains CPU, RAM, and an optional GPU
```

K3s, Tailscale, containerd, CNI state, and Kubernetes networking stay inside the container. No host networking or Kubernetes ports are published, so applications on the workstation keep their normal host port namespace.

The appliance uses one container because K3s's supported Tailscale integration expects the Tailscale CLI, `tailscaled`, `tailscale0`, and Flannel in the same network namespace. Tailscale authenticates before K3s starts; K3s then uses its native Tailscale VPN provider to advertise each node's pod route.

## Before You Start

Install Docker and Docker Compose on every computer. Do not install K3s or Tailscale on the host.

Create a reusable, pre-approved Tailscale auth key. A tagged key is recommended so device-key expiry is disabled. K3s nodes advertise their assigned pod subnets through Tailscale, so configure the tailnet once to approve the cluster pod CIDR and permit node and pod traffic. For the default `10.42.0.0/16` pod CIDR, a policy can include:

```json
{
  "tagOwners": {
    "tag:k3s": ["autogroup:admin"]
  },
  "autoApprovers": {
    "routes": {
      "10.42.0.0/16": ["tag:k3s"]
    }
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:k3s", "10.42.0.0/16"],
      "dst": ["tag:k3s:*", "10.42.0.0/16:*"]
    }
  ]
}
```

Create the auth key with `tag:k3s`. Without `autoApprovers`, routes must be approved manually whenever a new node joins.

## 1. Server Setup

On the first computer:

```bash
git clone https://github.com/shiukaheng/k3s-cuda
cd k3s-cuda
cp .env.example .env
```

Set at least:

```env
K3S_ROLE=server
K3S_SERVER=
K3S_TOKEN=

TS_AUTHKEY=tskey-auth-replace-me
TS_HOSTNAME=k3s-server
TS_CONTROL_URL=

COMPOSE_FILE=compose.yaml
```

For an NVIDIA computer, use `COMPOSE_FILE=compose.yaml:compose.gpu.yaml` after completing the GPU prerequisites below.

Start the appliance:

```bash
docker compose up -d
./scripts/status.sh
```

Generate a worker configuration after the server is ready:

```bash
./scripts/get-token.sh
```

The command prints the server's Tailscale IP and generated K3s token. It does not print your Tailscale auth key.

## 2. Worker Setup

On every worker computer:

```bash
git clone https://github.com/shiukaheng/k3s-cuda
cd k3s-cuda
cp .env.example .env
```

Use the values from `./scripts/get-token.sh`, add the Tailscale auth key, and choose a unique Tailscale hostname:

```env
K3S_ROLE=agent
K3S_SERVER=100.x.y.z
K3S_TOKEN=K10...

TS_AUTHKEY=tskey-auth-replace-me
TS_HOSTNAME=k3s-worker-b
TS_CONTROL_URL=

COMPOSE_FILE=compose.yaml
```

Then run:

```bash
docker compose up -d
./scripts/status.sh
```

`K3S_SERVER` may also be the server's MagicDNS name, such as `k3s-server`. The Tailscale IP printed by `get-token.sh` is the most deterministic choice.

## 3. GPU Prerequisites

On an NVIDIA machine, install the matching host driver and NVIDIA Container Toolkit, then configure Docker according to NVIDIA's installation instructions. This must succeed:

```bash
docker run --rm --gpus all \
  nvidia/cuda:12.8.1-base-ubuntu24.04 nvidia-smi
```

Select the GPU Compose override in `.env`:

```env
COMPOSE_FILE=compose.yaml:compose.gpu.yaml
```

Now `docker compose up -d` injects the host driver and GPUs. The appliance configures CDI, and the cluster-wide NVIDIA device plugin advertises `nvidia.com/gpu` on that node.

Docker Compose cannot make a GPU reservation optional: `gpus: all` fails before the container starts when NVIDIA support is absent. Keeping that one reservation in an override is what allows the same image and base configuration to work safely on CPU-only computers.

## 4. CPU-Only Setup

No NVIDIA packages are needed. Keep:

```env
COMPOSE_FILE=compose.yaml
```

The entrypoint detects that no driver was injected, skips GPU setup, and starts a normal CPU K3s node. The NVIDIA device-plugin DaemonSet remains healthy but advertises no GPU resources on that node.

## 5. Headscale Setup

Set the externally reachable Headscale control URL on every node:

```env
TS_CONTROL_URL=https://headscale.example.com
```

Use a reusable Headscale pre-auth key as `TS_AUTHKEY`. Headscale must approve the advertised pod routes and allow traffic between the node identities and `10.42.0.0/16`, equivalent to the Tailscale policy above.

## 6. Verify The Cluster

Show appliance status:

```bash
./scripts/status.sh
```

On the server, inspect all nodes:

```bash
docker compose exec k3s k3s kubectl get nodes -o wide
```

Test pod connectivity in both directions between every node:

```bash
./scripts/test-network.sh
```

On a GPU cluster, test scheduling and CDI injection:

```bash
docker compose exec -T k3s k3s kubectl apply -f - \
  < manifests/gpu-test-portable.yaml
docker compose exec k3s k3s kubectl wait \
  --for=jsonpath='{.status.phase}'=Succeeded \
  pod/k3s-gpu-test-portable --timeout=180s
docker compose exec k3s k3s kubectl logs k3s-gpu-test-portable
```

Kubernetes workloads request a GPU normally:

```yaml
resources:
  limits:
    nvidia.com/gpu: 1
```

Stop or restart the appliance without losing identity:

```bash
docker compose down
docker compose up -d
```

K3s, kubelet, CNI, and Tailscale identity state are stored in named Docker volumes. To intentionally delete the node and its local state:

```bash
docker compose down -v
```

## 7. Troubleshooting

Check status and logs first:

```bash
./scripts/status.sh
docker compose logs --tail=200 k3s
```

If Tailscale connects but the Kubernetes node is not Ready, verify that the node and its advertised pod route are approved and that the tailnet policy allows `tag:k3s` and `10.42.0.0/16` to communicate.

If a MagicDNS server name does not resolve, use the server's `100.x.y.z` address from `./scripts/get-token.sh`.

If a GPU is not detected, verify `COMPOSE_FILE=compose.yaml:compose.gpu.yaml` and rerun the CUDA Docker test from the GPU prerequisites. CPU hosts must not select the GPU override.

No host ports are published by default. K3s Services, NodePorts, and LoadBalancers remain in the appliance's network namespace. Publish a specific service explicitly only when you want it exposed on the workstation.

The K3s Tailscale provider is currently experimental. This appliance intentionally supports one server with distributed agents; K3s does not support embedded-etcd control-plane nodes distributed through this mode.

## Image Contents

The image starts directly from `rancher/k3s:v1.36.0-k3s1` and does not replace K3s or embedded containerd. It adds Tailscale, NVIDIA CDI tooling, the NVIDIA device plugin, and a small lifecycle entrypoint. The image contains no NVIDIA driver or CUDA toolkit.

The NixOS compatibility path copies Docker-injected `nvidia-smi` inside the appliance and changes its ELF interpreter only when it points into `/nix/store`. It never modifies the host.

Git tags matching `v*` publish `linux/amd64` images to `ghcr.io/shiukaheng/k3s-cuda`.
