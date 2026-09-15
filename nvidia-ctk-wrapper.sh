#!/bin/sh
set -eu

export LD_LIBRARY_PATH=/lib/x86_64-linux-gnu
exec /usr/libexec/nvidia-ctk "$@"
