#!/usr/bin/env bash
set -euo pipefail

api="${PUBTO_AGENT_URL:-http://127.0.0.1:8788}"
command="${1:-help}"

case "$command" in
  health|capabilities|projects|relays|bindings)
    case "$command" in
      health) path=/v1/health ;;
      capabilities) path=/v1/capabilities ;;
      projects) path=/v1/projects ;;
      relays) path=/v1/relays ;;
      bindings) path=/v1/bindings ;;
    esac
    exec curl -fsS "$api$path"
    ;;
  create-project)
    name="${2:?project name required}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1]}))' "$name")
    exec curl -fsS -X POST "$api/v1/projects" -H 'content-type: application/json' --data "$payload"
    ;;
  publish)
    project_id="${2:?project id required}"
    name="${3:?endpoint name required}"
    kind="${4:?kind required: http|directory|tcp|websocket}"
    target="${5:?target required}"
    relay_id="${6:-default}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],kind:process.argv[2],target:process.argv[3],relayId:process.argv[4]}))' "$name" "$kind" "$target" "$relay_id")
    exec curl -fsS -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data "$payload"
    ;;
  start|stop|rotate|delete-entry)
    project_id="${2:?project id required}"
    entry_id="${3:?entry id required}"
    case "$command" in
      start|stop) exec curl -fsS -X POST "$api/v1/projects/$project_id/entries/$entry_id/$command" ;;
      rotate) exec curl -fsS -X POST "$api/v1/projects/$project_id/entries/$entry_id/rotate-address" ;;
      delete-entry) exec curl -fsS -X DELETE "$api/v1/projects/$project_id/entries/$entry_id" ;;
    esac
    ;;
  expire-30m)
    project_id="${2:?project id required}"
    entry_id="${3:?entry id required}"
    expires_at=$(node -e 'process.stdout.write(new Date(Date.now()+30*60*1000).toISOString())')
    payload=$(node -e 'process.stdout.write(JSON.stringify({expiresAt:process.argv[1]}))' "$expires_at")
    exec curl -fsS -X PUT "$api/v1/projects/$project_id/entries/$entry_id/expiration" -H 'content-type: application/json' --data "$payload"
    ;;
  *)
    printf '%s\n' \
      'usage:' \
      '  pubtoctl.sh health|capabilities|projects|relays|bindings' \
      '  pubtoctl.sh create-project NAME' \
      '  pubtoctl.sh publish PROJECT_ID NAME KIND TARGET [RELAY_ID]' \
      '  pubtoctl.sh start|stop|rotate|delete-entry PROJECT_ID ENTRY_ID' \
      '  pubtoctl.sh expire-30m PROJECT_ID ENTRY_ID' >&2
    exit 2
    ;;
esac
