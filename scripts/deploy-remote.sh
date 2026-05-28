#!/usr/bin/env bash
set -euo pipefail

REMOTE_ROOT="${1:-/opt/vozacki}"
COMPOSE_FILE="${REMOTE_ROOT}/docker-compose.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "Missing ${COMPOSE_FILE}" >&2
  exit 1
fi

mkdir -p "${REMOTE_ROOT}/traefik/acme"
touch "${REMOTE_ROOT}/traefik/acme/acme.json"
chmod 600 "${REMOTE_ROOT}/traefik/acme/acme.json"

cd "${REMOTE_ROOT}"
if ! docker network inspect web >/dev/null 2>&1; then
  docker network create web
fi
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
