#!/usr/bin/env bash
set -euo pipefail

api="${PUBTO_AGENT_URL:-}"
if [[ -z "$api" ]] && command -v node >/dev/null 2>&1; then
  api=$(node -e '
const fs=require("fs"),os=require("os"),path=require("path");
const root=process.platform==="darwin"?path.join(os.homedir(),"Library","Application Support"):process.platform==="win32"?(process.env.APPDATA||path.join(os.homedir(),"AppData","Roaming")):(process.env.XDG_CONFIG_HOME||path.join(os.homedir(),".config"));
try{const value=JSON.parse(fs.readFileSync(path.join(root,"pubto","agent-discovery.json"),"utf8")).url||"";const parsed=new URL(value);if(parsed.protocol!=="http:"||!["127.0.0.1","localhost","[::1]"].includes(parsed.hostname))process.exit(1);process.stdout.write(value.replace(/\/$/,""))}catch{process.exit(1)}
' 2>/dev/null || true)
fi
if [[ -z "$api" ]]; then
  printf '%s\n' 'Pubto Desktop Agent is not running or its local discovery record is unavailable.' >&2
  exit 1
fi
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
    kind="${4:?kind required: http|directory|website|tcp|websocket}"
    target="${5:?target required}"
    relay_id="${6:-default}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],kind:process.argv[2],target:process.argv[3],relayId:process.argv[4]}))' "$name" "$kind" "$target" "$relay_id")
    exec curl -fsS -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data "$payload"
    ;;
  collection)
    project_id="${2:?project id required}"
    name="${3:?collection name required}"
    description="${4:-}"
    entry_ids="${5:?comma-separated entry ids required}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],description:process.argv[2],entryIds:process.argv[3].split(",").map((id)=>id.trim()).filter(Boolean)}))' "$name" "$description" "$entry_ids")
    curl -fsS -X PUT "$api/v1/homepage" -H 'content-type: application/json' --data "$payload" >/dev/null
    project_json=$(curl -fsS "$api/v1/projects/$project_id")
    if ! node -e 'const p=JSON.parse(process.argv[1]);process.exit((p.entries||[]).some((e)=>e.target==="pubto://homepage")?0:1)' "$project_json"; then
      curl -fsS -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data '{"name":"Collection","kind":"http","target":"pubto://homepage","relayId":"default"}'
    else
      printf '%s\n' "$project_json"
    fi
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
      '  pubtoctl.sh collection PROJECT_ID NAME DESCRIPTION ENTRY_ID[,ENTRY_ID...]' \
      '  pubtoctl.sh start|stop|rotate|delete-entry PROJECT_ID ENTRY_ID' \
      '  pubtoctl.sh expire-30m PROJECT_ID ENTRY_ID' >&2
    exit 2
    ;;
esac
