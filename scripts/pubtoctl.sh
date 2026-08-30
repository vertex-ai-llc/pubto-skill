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
  printf '%s\n' 'Pubto Desktop is unavailable. Start Pubto Desktop and try again.' >&2
  exit 1
fi

# Keep the helper's output suitable for an AI conversation.  In particular,
# curl diagnostics would otherwise echo the loopback management URL.  The
# CLI itself performs the same discovery and user-facing redaction.
request() {
  local body
  if ! body=$(curl -fsS "$@" 2>/dev/null); then
    printf '%s\n' 'Pubto Desktop is unavailable. Start Pubto Desktop and try again.' >&2
    return 1
  fi
  printf '%s\n' "$body"
}
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
    request "$api$path"
    ;;
  create-project)
    name="${2:?project name required}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1]}))' "$name")
    request -X POST "$api/v1/projects" -H 'content-type: application/json' --data "$payload"
    ;;
  publish)
    project_id="${2:?project id required}"
    name="${3:?endpoint name required}"
    kind="${4:?kind required: http|directory|website|tcp|websocket}"
    target="${5:?target required}"
    relay_id="${6:-default}"
    client_key="${7:-}"
    if [[ -z "$client_key" ]]; then
      client_key=$(node -e 'const c=require("crypto");process.stdout.write("skill-"+c.createHash("sha256").update(process.argv[1]+"\0"+process.argv[2]).digest("hex").slice(0,20))' "$kind" "$target")
    fi
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],kind:process.argv[2],target:process.argv[3],relayId:process.argv[4],clientKey:process.argv[5]}))' "$name" "$kind" "$target" "$relay_id" "$client_key")
    request -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data "$payload"
    ;;
  publish-new)
    project_id="${2:?project id required}"
    name="${3:?endpoint name required}"
    kind="${4:?kind required: http|directory|website|tcp|websocket}"
    target="${5:?target required}"
    relay_id="${6:-default}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],kind:process.argv[2],target:process.argv[3],relayId:process.argv[4]}))' "$name" "$kind" "$target" "$relay_id")
    request -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data "$payload"
    ;;
  collection)
    project_id="${2:?project id required}"
    name="${3:?collection name required}"
    description="${4:-}"
    entry_ids="${5:?comma-separated entry ids required}"
    payload=$(node -e 'process.stdout.write(JSON.stringify({name:process.argv[1],description:process.argv[2],entryIds:process.argv[3].split(",").map((id)=>id.trim()).filter(Boolean)}))' "$name" "$description" "$entry_ids")
    request -X PUT "$api/v1/homepage" -H 'content-type: application/json' --data "$payload" >/dev/null
    collection_payload=$(node -e 'process.stdout.write(JSON.stringify({name:"Collection",kind:"http",target:"pubto://homepage",relayId:"default",clientKey:"collection:"+process.argv[1]}))' "$project_id")
    request -X POST "$api/v1/projects/$project_id/entries" -H 'content-type: application/json' --data "$collection_payload"
    ;;
  start|stop|rotate|delete-entry)
    project_id="${2:?project id required}"
    entry_id="${3:?entry id required}"
    case "$command" in
      start|stop) request -X POST "$api/v1/projects/$project_id/entries/$entry_id/$command" ;;
      rotate) request -X POST "$api/v1/projects/$project_id/entries/$entry_id/rotate-address" ;;
      delete-entry) request -X DELETE "$api/v1/projects/$project_id/entries/$entry_id" ;;
    esac
    ;;
  expire-30m)
    project_id="${2:?project id required}"
    entry_id="${3:?entry id required}"
    expires_at=$(node -e 'process.stdout.write(new Date(Date.now()+30*60*1000).toISOString())')
    payload=$(node -e 'process.stdout.write(JSON.stringify({expiresAt:process.argv[1]}))' "$expires_at")
    request -X PUT "$api/v1/projects/$project_id/entries/$entry_id/expiration" -H 'content-type: application/json' --data "$payload"
    ;;
  remark|clear-remark)
    project_id="${2:?project id required}"
    entry_id="${3:?entry id required}"
    text="${4:-}"
    if [[ "$command" == "remark" && -z "$text" ]]; then
      printf '%s\n' 'remark text required' >&2
      exit 2
    fi
    [[ "$command" == "clear-remark" ]] && text=""
    payload=$(node -e 'process.stdout.write(JSON.stringify({remark:process.argv[1]}))' "$text")
    request -X PUT "$api/v1/projects/$project_id/entries/$entry_id/remark" -H 'content-type: application/json' --data "$payload"
    ;;
  *)
    printf '%s\n' \
      'usage:' \
      '  pubtoctl.sh health|capabilities|projects|relays|bindings' \
      '  pubtoctl.sh create-project NAME' \
      '  pubtoctl.sh publish PROJECT_ID NAME KIND TARGET [RELAY_ID] [CLIENT_KEY]' \
      '  pubtoctl.sh publish-new PROJECT_ID NAME KIND TARGET [RELAY_ID]' \
      '  pubtoctl.sh collection PROJECT_ID NAME DESCRIPTION ENTRY_ID[,ENTRY_ID...]' \
      '  pubtoctl.sh start|stop|rotate|delete-entry PROJECT_ID ENTRY_ID' \
      '  pubtoctl.sh expire-30m PROJECT_ID ENTRY_ID' \
      '  pubtoctl.sh remark PROJECT_ID ENTRY_ID TEXT' \
      '  pubtoctl.sh clear-remark PROJECT_ID ENTRY_ID' >&2
    exit 2
    ;;
esac
