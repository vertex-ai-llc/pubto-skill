---
name: pubto-publish
description: Publish, inspect, verify, edit, expire, stop, rotate, and remove local HTTP/HTTPS, WS/WSS, file, safe directory, static website, or TCP endpoints through Pubto. Use when an AI needs to preview a local project, expose a port or API, share a document, choose a Relay, map a remote endpoint to localhost, diagnose an unavailable Pubto publication, or troubleshoot browser CORS and preflight failures.
---

# Pubto Publish

Use the installed `pubto` CLI first. It discovers the running Desktop Agent's ephemeral loopback address automatically. If the CLI is unavailable, use `scripts/pubtoctl.sh`, which reads the same discovery record. Never publish the Agent API itself.

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

The installers select the matching artifact from Pubto's HTTPS release manifest, require its SHA-256 checksum, preserve Desktop settings and local SQLite data, launch Pubto, and verify the ephemeral loopback Agent through its discovery record. Do not use `--yes` unless the user explicitly approved installation. Do not bypass macOS Gatekeeper, Windows UAC, or package signature warnings. If the manifest has no compatible signed artifact, report that publishing cannot start on that platform.

## Publish

Choose exactly one source:

```sh
pubto publish --port 3000 --name Frontend --duration 30m
pubto publish --url https://127.0.0.1:8443
pubto publish --ws-port 8998
pubto publish --tcp 5432
pubto publish --file ./report.docx
pubto publish --dir ./documents
pubto publish --website ./dist
```

Treat a Project as a name-only group. Each Endpoint has one independent random address, target, Relay, lifecycle, password, expiry, and quota policy. Creation publishes immediately; do not issue a second project-level publish action. Reuse the first suitable Project unless the user asks for another.

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
```

Use `scripts/pubtoctl.sh` or the typed loopback API described by `GET /v1/capabilities` for advanced operations:

```text
PUT    /v1/projects/{projectId}/entries/{entryId}                  edit name, kind, target, relayId
DELETE /v1/projects/{projectId}/entries/{entryId}                  revoke and delete
POST   /v1/projects/{projectId}/entries/{entryId}/start|stop
PUT    /v1/projects/{projectId}/entries/{entryId}/expiration
PUT    /v1/projects/{projectId}/entries/{entryId}/password
POST   /v1/projects/{projectId}/entries/{entryId}/rotate-address
POST   /v1/projects/{projectId}/entries/{entryId}/report
PUT    /v1/homepage                                                   update a multi-endpoint Collection
```

Changing a password invalidates old passwords and cookies immediately. Password plaintext goes only to the loopback Agent, which stores a salted digest. Deleting or rotating an Endpoint must make its old address return 404.

## Safety

- Ask before publishing databases, caches, SSH, admin panels, LAN targets, or public Internet targets.
- Prefer a 30-minute duration for sensitive temporary Endpoints.
- Never print Relay, Control, Cloudflare, database, or application secrets.
- Treat TCP public addresses as raw sockets, not browser URLs.
- Delete a temporary Endpoint when the requested use is complete.
