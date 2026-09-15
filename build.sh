#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="k3s-gpu-test:v1.36.0-k3s1"

docker build --build-arg K3S_VERSION=v1.36.0-k3s1 --tag "$image" "$root"
