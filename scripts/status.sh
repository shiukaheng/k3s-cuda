#!/bin/sh
set -eu

docker compose exec -T k3s appliance-status
