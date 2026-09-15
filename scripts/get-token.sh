#!/bin/sh
set -eu

role=$(docker compose exec -T k3s cat /run/appliance/role)
[ "$role" = server ] || { printf 'This node is not a server.\n' >&2; exit 1; }

server=$(docker compose exec -T k3s tailscale ip -4)
token=$(docker compose exec -T k3s cat /var/lib/rancher/k3s/server/node-token)

cat <<EOF
K3S_ROLE=agent
K3S_SERVER=$server
K3S_TOKEN=$token
TS_AUTHKEY=<reusable-or-preapproved-auth-key>
TS_HOSTNAME=<unique-worker-name>
TS_CONTROL_URL=
EOF
