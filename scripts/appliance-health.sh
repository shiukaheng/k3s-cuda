#!/bin/sh
set -eu

tailscale status --json | grep -q '"BackendState": "Running"'
[ -s /run/appliance/k3s.pid ]
kill -0 "$(cat /run/appliance/k3s.pid)"
[ "$(wget -qO- http://127.0.0.1:10248/healthz)" = ok ]
