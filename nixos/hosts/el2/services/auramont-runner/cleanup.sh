#!/bin/bash
# This container runs exactly one Auramont job at a time. Its Docker daemon and HOME
# are private to CI; no host containers, volumes or user SSH files are shared.
set -euo pipefail
docker ps --all --quiet | xargs --no-run-if-empty docker rm --force --volumes
docker volume prune --all --force
docker network prune --force
docker image prune --all --force --filter until=168h
docker builder prune --force --keep-storage 40GB
rm -rf -- "$HOME/.ssh" "$HOME/.docker"
