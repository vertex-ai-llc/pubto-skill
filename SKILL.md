---
name: pubto-publish
description: Publish, inspect, verify, edit, expire, stop, rotate, and remove local HTTP/HTTPS, WS/WSS, file, safe directory, static website, or TCP endpoints through Pubto. Use when an AI needs to preview a local project, expose a port or API, share a document, choose a Relay, map a remote endpoint to localhost, diagnose an unavailable Pubto publication, or troubleshoot browser CORS and preflight failures.
---

# Pubto Publish

Use the installed `pubto` CLI first. It discovers the running Desktop Agent's ephemeral loopback address automatically. If the CLI is unavailable, use `scripts/pubtoctl.sh`, which reads the same discovery record. Never publish the Agent API itself.

## Install and update Pubto

Use one of the official channels below. They all install the same Desktop UI, bundled local Agent, and matching `pubto` CLI; do not install a second Agent from a package manager.

- **Desktop download (recommended):** open `https://pubto.dev/downloads`, download the macOS DMG or Windows x64 installer, and launch Pubto. The first-run With AI guide can install the CLI for the current user. macOS installs the CLI at `~/.local/bin/pubto`; Windows installs it at `%LOCALAPPDATA%\\Pubto\\bin` and adds that directory to the user's PATH.
- **Homebrew (macOS):** after the `vertex-ai-llc/pubto` release is published, run `brew tap vertex-ai-llc/pubto` and `brew install --cask pubto`. The Cask downloads the signed DMG from the public `vertex-ai-llc/pubto-downloads` release; Homebrew is not a build system for Pubto.
- **Standalone CLI:** use the platform package shown under **CLI** on the downloads page when a GUI is not wanted. Keep the CLI and Desktop on the same release version so the local Agent API remains compatible.

The public Skill repository is `https://github.com/vertex-ai-llc/pubto-skill`. Install it only into the tool you actually use; installing it in one tool does not enable another tool. To update, pull or clone the repository again into the same managed directory, or use Desktop's **With AI** page. To uninstall, remove only the `pubto-publish` directory that was created by Pubto; never remove a user-owned directory that lacks Pubto's managed marker.

| Tool | Skill directory |
| --- | --- |
| Codex CLI | `~/.codex/skills/pubto-publish` |
| Claude Code | `~/.claude/skills/pubto-publish` |
| OpenCode | `~/.config/opencode/skills/pubto-publish` |
| Grok CLI | `~/.grok/skills/pubto-publish` |
| pi coding agent | `~/.pi/agent/skills/pubto-publish` |

Gemini CLI and Qwen Code use the `/pubto` managed command written by Desktop, not a second transport or Agent.

## Desktop bootstrap

If Pubto Desktop is missing, tell the user that publishing requires the local Desktop Agent and ask for confirmation before installing anything. After confirmation, use the platform installer bundled with this skill:

```sh
# macOS Apple Silicon or Intel
scripts/install-desktop.sh --yes
```

```powershell
# Windows x64
powershell -ExecutionPolicy Bypass -File scripts/install-desktop.ps1 -Yes
```

To check without changing the machine, run the same installer with `--check` on macOS or `-Check` on Windows. It reads the signed release manifest, detects the local Agent through the ephemeral discovery record, and reports whether Desktop is absent, current, or on an older release. When an update is available, rerun the installer with explicit user confirmation (`--yes` or `-Yes`); the installer verifies the checksum, preserves local data, and performs a rollback if the new app or Agent is unhealthy.

The installers select the matching artifact from Pubto's HTTPS release manifest, require its SHA-256 checksum, preserve Desktop settings and local SQLite data, launch Pubto, and verify that the ephemeral loopback Agent reports the manifest version. A failed install or mismatched Agent restores the previous app and local data. Do not use `--yes` unless the user explicitly approved installation. Do not bypass macOS Gatekeeper, Windows UAC, or package signature warnings. If the manifest has no compatible artifact, report that publishing cannot start on that platform.

## Publish

Choose exactly one source:

```sh
pubto publish --port 3000 --name Frontend --key frontend --duration 30m
pubto publish --url https://127.0.0.1:8443
pubto publish --ws-port 8998
pubto publish --tcp 5432
pubto publish --file ./report.docx
pubto publish --dir ./documents
pubto publish --website ./dist
```

Treat a Project as a name-only group. Each Endpoint has one independent random address, target, Relay, lifecycle, password, expiry, and quota policy. Creation publishes immediately; do not issue a second project-level publish action. Reuse the first suitable Project unless the user asks for another.

Publishing is idempotent by default. The CLI derives a stable `clientKey` from the protocol and target, so repeating the same command in the same Project reuses the existing `endpointId`, slug, and public address. Pass an explicit stable `--key` such as `frontend` when the logical Endpoint may move to another port or target; the same Project and key updates that Endpoint instead of creating a duplicate. Use `--new` only when the user explicitly wants another public address. Treat the returned `endpointId` as the authoritative identifier for later commands.

Use HTTP for HTTP/HTTPS targets, WebSocket for WS/WSS targets, and TCP for PostgreSQL, MySQL, Redis, SSH, MQTT, and other byte streams. Use `--dir` for a safe file listing that never executes `index.html`; use `--website` when a selected folder should serve `index.html`. Published files open in the visitor's public browser Viewer; unsupported formats remain downloadable.

After creation, read the returned Endpoint until it reports `running`, a `publicUrl`, and its reachability state. Verify with a read-only protocol-appropriate request without application credentials, then report the exact public address.

## Collections

When someone needs to share several endpoints, files, or directories as one handoff, create a Collection inside the selected Project. A Collection is a generated public page containing multiple existing Endpoint links; it is not another transport or another copy of an Endpoint. Ask for a name, optional description, and the Endpoint IDs to include, then update `PUT /v1/homepage` with `{name,description,entryIds}` and publish the special `pubto://homepage` Endpoint in that Project if it does not already exist. The Desktop calls this action `New collection`; do not describe or add a separate `Publish Page` step.

## Browser APIs and CORS

Do not equate a reachable public URL or an HTTP 200 response with browser compatibility. For a browser API, identify the exact frontend Origin (scheme, host, and port), request URL, method, and non-simple request headers. If the frontend and API have the same public Origin, the browser has no CORS boundary: an application error such as `cross-origin writes are not allowed` means the source's CSRF/Origin guard does not trust its configured public Origin. Fix that source allowlist without enabling wildcard CORS.

If the frontend and API Origins differ, run the read-only preflight check before asking the user to change code:

```sh
scripts/check-cors.sh https://PUBLIC_HOST/api/resource https://app.example.test POST 'content-type,authorization'
```

The check sends `OPTIONS` with `Origin`, `Access-Control-Request-Method`, and (when supplied) `Access-Control-Request-Headers`. Confirm that the response is a successful 2xx preflight and that:

- `Access-Control-Allow-Origin` exactly matches the trusted Origin, or is `*` only for non-credentialed public reads;
- `Access-Control-Allow-Methods` contains the requested method;
- `Access-Control-Allow-Headers` contains each requested header;
- `Access-Control-Allow-Credentials: true` is present only when the application intentionally uses cookies or other credentialed browser requests.

If the tunnel returns an application JSON `4xx/5xx`, or `OPTIONS` is rejected by the source, report that the tunnel is working and the source program's CORS/CSRF policy is the fix point. Configure the source with an explicit Origin allowlist and a dedicated `OPTIONS` handler. Do not make Pubto strip or forge `Origin`, reflect arbitrary Origins, or add `Access-Control-Allow-Origin: *` by default: that can turn a protected write API into a cross-site request surface. With cookies, `*` is invalid and a permissive reflected Origin creates CSRF risk; require authentication, CSRF protection, and short-lived or password-protected publications where appropriate.

For WebSocket endpoints, CORS headers do not authorize the upgrade. Check the source's `Origin` allowlist and the `101 Switching Protocols` handshake separately. TCP endpoints have no browser CORS layer and must be treated as raw public sockets.

## Operate

```sh
pubto status
pubto list
pubto start --endpoint ENTRY_ID
pubto stop --endpoint ENTRY_ID
pubto delete --endpoint ENTRY_ID
pubto remark --endpoint ENTRY_ID --text "Review build for the mobile team"
pubto remark --endpoint ENTRY_ID --clear
```

Use `scripts/pubtoctl.sh` or the typed loopback API described by `GET /v1/capabilities` for advanced operations:

```text
PUT    /v1/projects/{projectId}/entries/{entryId}                  edit name, kind, target, relayId
DELETE /v1/projects/{projectId}/entries/{entryId}                  revoke and delete
POST   /v1/projects/{projectId}/entries/{entryId}/start|stop
PUT    /v1/projects/{projectId}/entries/{entryId}/expiration
PUT    /v1/projects/{projectId}/entries/{entryId}/password
PUT    /v1/projects/{projectId}/entries/{entryId}/remark              public recipient note, up to 500 characters
POST   /v1/projects/{projectId}/entries/{entryId}/rotate-address
POST   /v1/projects/{projectId}/entries/{entryId}/report
PUT    /v1/homepage                                                   update a multi-endpoint Collection
```

Changing a password invalidates old passwords and cookies immediately. Password plaintext goes only to the loopback Agent, which stores a salted digest. Deleting or rotating an Endpoint must make its old address return 404.

Use an Endpoint remark for context recipients should see after saving the Pub. Remarks are public metadata; never place credentials, private file paths, tokens, or internal-only notes in them. Creating an Endpoint does not require a remark, and normal Desktop creation never asks for one.

## Safety

- Ask before publishing databases, caches, SSH, admin panels, LAN targets, or public Internet targets.
- Prefer a 30-minute duration for sensitive temporary Endpoints.
- Never print Relay, Control, Cloudflare, database, or application secrets.
- Treat TCP public addresses as raw sockets, not browser URLs.
- Delete a temporary Endpoint when the requested use is complete.
