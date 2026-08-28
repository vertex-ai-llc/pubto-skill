#!/usr/bin/env bash
set -euo pipefail

manifest_url="${PUBTO_RELEASE_MANIFEST:-https://pubto.dev/downloads/manifest.json}"
manifest_file=""
assume_yes=false
dry_run=false
check_only=false

usage() {
  printf '%s\n' 'usage: install-desktop.sh [--manifest URL|FILE] [--yes] [--dry-run] [--check]'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      manifest_file="${2:?manifest value required}"
      shift 2
      ;;
    --yes)
      assume_yes=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --check)
      check_only=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'This installer supports macOS. Use install-desktop.ps1 on Windows.' >&2
  exit 1
fi

case "$(uname -m)" in
  arm64) architecture=arm64 ;;
  x86_64) architecture=amd64 ;;
  *)
    printf 'unsupported macOS architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/pubto-install.XXXXXX")
mount_dir="$work_dir/mount"
mounted=false
rollback_armed=false
rollback_done=false
cleanup() {
  if [[ "$mounted" == true ]]; then
    /usr/bin/hdiutil detach "$mount_dir" -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}

restore_previous() {
  [[ "$rollback_armed" == true && "$rollback_done" == false ]] || return 0
  rollback_done=true
  /usr/bin/osascript -e 'tell application "Pubto" to quit' >/dev/null 2>&1 || true
  /usr/bin/pkill -x pubto-agent >/dev/null 2>&1 || true
  /usr/bin/pkill -x Pubto >/dev/null 2>&1 || true
  for _ in {1..20}; do
    /usr/bin/pgrep -x Pubto >/dev/null 2>&1 || break
    sleep 0.25
  done
  for _ in {1..40}; do
    /usr/bin/pgrep -x pubto-agent >/dev/null 2>&1 || break
    sleep 0.25
  done
  rm -rf -- "$target_app" "$config_root" "$tauri_data_root"
  if [[ "$had_app" == true && -d "$backup_app" ]]; then
    /usr/bin/ditto "$backup_app" "$target_app" || true
  fi
  if [[ "$had_config" == true && -d "$backup_config" ]]; then
    /usr/bin/ditto "$backup_config" "$config_root" || true
  fi
  if [[ "$had_tauri_data" == true && -d "$backup_tauri_data" ]]; then
    /usr/bin/ditto "$backup_tauri_data" "$tauri_data_root" || true
  fi
  if [[ -d "$target_app" ]]; then
    /usr/bin/open "$target_app" >/dev/null 2>&1 || true
  fi
  printf '%s\n' 'Pubto Desktop installation failed; the previous app and local data were restored.' >&2
}

finish() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    restore_previous
  fi
  cleanup
  exit "$status"
}
trap finish EXIT

manifest_path="$work_dir/manifest.json"
if [[ -n "$manifest_file" && -f "$manifest_file" ]]; then
  cp "$manifest_file" "$manifest_path"
else
  [[ -n "$manifest_file" ]] && manifest_url="$manifest_file"
  if [[ "$manifest_url" != https://* ]]; then
    printf '%s\n' 'The release manifest URL must use HTTPS.' >&2
    exit 1
  fi
  /usr/bin/curl --fail --location --silent --show-error "$manifest_url" --output "$manifest_path"
fi

selection=$(/usr/bin/osascript -l JavaScript - "$manifest_path" "$architecture" <<'JXA'
function run(argv) {
  ObjC.import('Foundation');
  const path = $(argv[0]).stringByStandardizingPath;
  const data = $.NSData.dataWithContentsOfFile(path);
  if (!data) throw new Error('Unable to read release manifest');
  const object = ObjC.deepUnwrap($.NSJSONSerialization.JSONObjectWithDataOptionsError(data, 0, null));
  const artifacts = Array.isArray(object.artifacts) ? object.artifacts : [];
  const item = artifacts.find((candidate) =>
    candidate.component === 'desktop' && candidate.os === 'darwin' && candidate.arch === argv[1]
  );
  if (!item) throw new Error('No compatible Pubto Desktop artifact in the release manifest');
  return [item.url || '', item.sha256 || '', item.packageType || '', object.version || ''].join('\n');
}
JXA
)
artifact_url=$(printf '%s\n' "$selection" | sed -n '1p')
expected_sha=$(printf '%s\n' "$selection" | sed -n '2p' | tr '[:upper:]' '[:lower:]')
installer=$(printf '%s\n' "$selection" | sed -n '3p')
release_version=$(printf '%s\n' "$selection" | sed -n '4p')

if [[ "$artifact_url" != https://* || ! "$expected_sha" =~ ^[0-9a-f]{64}$ || "$installer" != "dmg" || ! "$release_version" =~ ^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$ ]]; then
  printf '%s\n' 'The selected Desktop artifact has invalid URL, checksum, or installer metadata.' >&2
  exit 1
fi

printf 'Pubto Desktop: macOS %s\n' "$architecture"
printf 'Package: %s\n' "$artifact_url"
if [[ "$check_only" == true ]]; then
  discovery="$HOME/Library/Application Support/pubto/agent-discovery.json"
  if [[ -f "$discovery" ]]; then
    agent_url=$(/usr/bin/plutil -extract url raw "$discovery" 2>/dev/null || true)
    if [[ "$agent_url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+/?$ ]]; then
      health=$(/usr/bin/curl --fail --silent "${agent_url%/}/v1/health" 2>/dev/null || true)
      if /usr/bin/osascript -l JavaScript - "$release_version" "$health" <<'JXA' >/dev/null 2>&1
function run(argv) {
  const object = JSON.parse(argv[1]);
  if (object.status !== 'ok' || object.component !== 'pubto-agent') throw new Error('agent unavailable');
  if (object.version === argv[0]) return 'up-to-date';
  throw new Error('update available');
}
JXA
      then
        printf 'Pubto Desktop is up to date (%s).\n' "$release_version"
      else
        printf 'Pubto Desktop update available: %s.\n' "$release_version"
      fi
      exit 0
    fi
  fi
  printf '%s\n' 'Pubto Desktop is not installed or its local Agent is not running.'
  exit 0
fi
if [[ "$dry_run" == true ]]; then
  printf '%s\n' 'Dry run complete; no package was downloaded or installed.'
  exit 0
fi

if [[ "$assume_yes" != true ]]; then
  printf '%s' 'Install or upgrade Pubto Desktop for this user? [y/N] '
  read -r answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || exit 0
fi

package_path="$work_dir/Pubto.dmg"
/usr/bin/curl --fail --location --silent --show-error "$artifact_url" --output "$package_path"
actual_sha=$(/usr/bin/shasum -a 256 "$package_path" | awk '{print tolower($1)}')
if [[ "$actual_sha" != "$expected_sha" ]]; then
  printf '%s\n' 'Pubto Desktop checksum verification failed.' >&2
  exit 1
fi

mkdir -p "$mount_dir" "$HOME/Applications"
/usr/bin/hdiutil attach "$package_path" -nobrowse -readonly -mountpoint "$mount_dir" -quiet
mounted=true
source_app=$(find "$mount_dir" -maxdepth 2 -type d -name 'Pubto.app' -print -quit)
if [[ -z "$source_app" ]]; then
  printf '%s\n' 'Pubto.app was not found in the verified disk image.' >&2
  exit 1
fi

target_app="$HOME/Applications/Pubto.app"
staged_app="$work_dir/Pubto.app"
backup_app="$work_dir/Pubto.previous.app"
config_root="$HOME/Library/Application Support/pubto"
tauri_data_root="$HOME/Library/Application Support/dev.pubto.desktop"
backup_config="$work_dir/pubto-config"
backup_tauri_data="$work_dir/tauri-data"
had_app=false
had_config=false
had_tauri_data=false
if [[ -d "$target_app" ]]; then
  had_app=true
fi
if [[ -d "$config_root" ]]; then
  /usr/bin/ditto "$config_root" "$backup_config"
  had_config=true
fi
if [[ -d "$tauri_data_root" ]]; then
  /usr/bin/ditto "$tauri_data_root" "$backup_tauri_data"
  had_tauri_data=true
fi
rollback_armed=true
/usr/bin/ditto "$source_app" "$staged_app"
if [[ -d "$target_app" ]]; then
  mv "$target_app" "$backup_app"
fi
mv "$staged_app" "$target_app"

/usr/bin/open "$target_app"
discovery="$HOME/Library/Application Support/pubto/agent-discovery.json"
health_path="$work_dir/health.json"
for _ in {1..30}; do
  if [[ -f "$discovery" ]]; then
    agent_url=$(/usr/bin/plutil -extract url raw "$discovery" 2>/dev/null || true)
    if [[ "$agent_url" =~ ^http://(127\.0\.0\.1|localhost|\[::1\]):[0-9]+/?$ ]] && /usr/bin/curl --fail --silent "${agent_url%/}/v1/health" --output "$health_path"; then
      if /usr/bin/osascript -l JavaScript - "$health_path" "$release_version" <<'JXA' >/dev/null 2>&1
function run(argv) {
  ObjC.import('Foundation');
  const path = $(argv[0]).stringByStandardizingPath;
  const data = $.NSData.dataWithContentsOfFile(path);
  if (!data) throw new Error('Unable to read Agent health');
  const object = ObjC.deepUnwrap($.NSJSONSerialization.JSONObjectWithDataOptionsError(data, 0, null));
  if (object.status !== 'ok' || object.component !== 'pubto-agent' || object.version !== argv[1]) {
    throw new Error('Agent health did not match the installed release');
  }
  return 'ok';
}
JXA
      then
        rollback_armed=false
        printf '%s\n' 'Pubto Desktop is installed and its local Agent is ready.'
        exit 0
      fi
    fi
  fi
  sleep 1
done

printf '%s\n' 'Pubto Desktop was installed, but the local Agent did not become ready within 30 seconds.' >&2
exit 1
