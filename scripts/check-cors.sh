#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'usage: check-cors.sh URL ORIGIN [METHOD] [REQUEST_HEADERS]' \
    'example: check-cors.sh https://pub.example.test/api https://app.example.test POST content-type,authorization' >&2
}

if [[ $# -lt 2 || $# -gt 4 ]]; then
  usage
  exit 2
fi

url="$1"
origin="$2"
method="${3:-POST}"
requested_headers="${4:-}"

if ! command -v curl >/dev/null 2>&1; then
  printf '%s\n' 'curl is required.' >&2
  exit 127
fi

headers_file=$(mktemp "${TMPDIR:-/tmp}/pubto-cors.XXXXXX")
trap 'rm -f "$headers_file"' EXIT

curl_args=(
  --silent --show-error --dump-header "$headers_file" --output /dev/null
  --connect-timeout 10 --max-time 20
  -X OPTIONS "$url"
  -H "Origin: $origin"
  -H "Access-Control-Request-Method: $method"
)
if [[ -n "$requested_headers" ]]; then
  curl_args+=( -H "Access-Control-Request-Headers: $requested_headers" )
fi

status=$(curl "${curl_args[@]}" -w '%{http_code}')
printf 'Preflight status: %s\n' "$status"
printf 'Response headers:\n'
sed -n '/^[[:space:]]*$/q;p' "$headers_file"

header_value() {
  awk -F: -v wanted="$1" '
    BEGIN { IGNORECASE = 1 }
    tolower($1) == tolower(wanted) {
      value = $0
      sub(/^[^:]*:[[:space:]]*/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$headers_file"
}

allow_origin=$(header_value Access-Control-Allow-Origin)
allow_methods=$(header_value Access-Control-Allow-Methods)
allow_headers=$(header_value Access-Control-Allow-Headers)
allow_credentials=$(header_value Access-Control-Allow-Credentials)

printf 'Allow-Origin: %s\n' "${allow_origin:-<missing>}"
printf 'Allow-Methods: %s\n' "${allow_methods:-<missing>}"
printf 'Allow-Headers: %s\n' "${allow_headers:-<missing>}"
printf 'Allow-Credentials: %s\n' "${allow_credentials:-<missing>}"

ok=true
if [[ "$status" -lt 200 || "$status" -ge 300 ]]; then
  ok=false
  printf '%s\n' 'Result: preflight was rejected or failed.'
fi
if [[ "$allow_origin" != "$origin" && "$allow_origin" != '*' ]]; then
  ok=false
  printf '%s\n' 'Result: the requested Origin is not allowed.'
fi
if [[ "$allow_origin" == '*' && -n "$allow_credentials" && "$allow_credentials" != 'false' ]]; then
  ok=false
  printf '%s\n' 'Result: wildcard Origin cannot be used with credentials.'
fi
contains_token() {
  awk -v list="${1:-}" -v wanted="${2:-}" '
    BEGIN {
      n = split(list, values, ",")
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[i])
        if (tolower(values[i]) == tolower(wanted)) exit 0
      }
      exit 1
    }
  '
}
if [[ -z "$allow_methods" ]] || ! contains_token "$allow_methods" "$method"; then
  ok=false
  printf '%s\n' "Result: method $method is not listed in Allow-Methods."
fi
if [[ -n "$requested_headers" && "$allow_headers" != '*' ]]; then
  while IFS= read -r requested_header; do
    requested_header=$(printf '%s' "$requested_header" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [[ -z "$requested_header" ]] && continue
    if ! contains_token "$allow_headers" "$requested_header"; then
      ok=false
      printf '%s\n' "Result: header $requested_header is not listed in Allow-Headers."
    fi
  done < <(printf '%s' "$requested_headers" | tr ',' '\n')
fi

if [[ "$ok" == true ]]; then
  printf '%s\n' 'Result: preflight headers look compatible; application auth and source policy still apply.'
else
  printf '%s\n' 'Result: fix the source application CORS/OPTIONS policy; do not make Pubto rewrite Origin by default.'
  exit 1
fi
