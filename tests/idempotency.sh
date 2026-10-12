#!/bin/sh
# Host side: run the bootstrap twice in a clean container and fail if the
# second run changes anything. Same script locally and in CI.
#
#   tests/idempotency.sh [image]          # default ubuntu:24.04
#   CONTAINER_ENGINE=docker tests/idempotency.sh
set -eu

IMAGE=${1:-ubuntu:24.04}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

ENGINE=${CONTAINER_ENGINE:-}
if [ -z "$ENGINE" ]; then
    for e in podman docker; do
        if command -v "$e" >/dev/null 2>&1; then
            ENGINE=$e
            break
        fi
    done
fi
[ -n "$ENGINE" ] || {
    echo "error: need podman or docker (or set CONTAINER_ENGINE)" >&2
    exit 2
}

echo "==> $ENGINE run $IMAGE"
exec "$ENGINE" run --rm -v "$ROOT:/src:ro" "$IMAGE" sh /src/tests/in-container.sh
