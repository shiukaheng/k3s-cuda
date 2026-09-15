#!/usr/bin/env bash
set -euo pipefail

remove_image=false
if [[ "${1:-}" == "--image" ]]; then
  remove_image=true
fi

docker rm -f k3s-gpu-test-server >/dev/null 2>&1 || true
docker volume ls --quiet --filter 'name=^k3s-gpu-test' | xargs --no-run-if-empty docker volume rm
docker network ls --quiet --filter 'name=^k3s-gpu-test' | xargs --no-run-if-empty docker network rm
if "$remove_image"; then
  docker image rm k3s-gpu-test:v1.36.0-k3s1 >/dev/null 2>&1 || true
fi
