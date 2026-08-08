---
name: pubto-publish
description: Publish, inspect, verify, edit, expire, stop, rotate, and remove local HTTP/HTTPS, WS/WSS, file, safe directory, static website, or TCP endpoints through Pubto. Use when an AI needs to preview a local project, expose a port or API, share a document, choose a Relay, map a remote endpoint to localhost, or diagnose an unavailable Pubto publication.
---

# Pubto Publish

Use the installed `pubto` CLI first. It discovers the running Desktop Agent's ephemeral loopback address automatically. If the CLI is unavailable, use `scripts/pubtoctl.sh`, which reads the same discovery record. Never publish the Agent API itself.

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
```

Changing a password invalidates old passwords and cookies immediately. Password plaintext goes only to the loopback Agent, which stores a salted digest. Deleting or rotating an Endpoint must make its old address return 404.

## Safety

- Ask before publishing databases, caches, SSH, admin panels, LAN targets, or public Internet targets.
- Prefer a 30-minute duration for sensitive temporary Endpoints.
- Never print Relay, Control, Cloudflare, database, or application secrets.
- Treat TCP public addresses as raw sockets, not browser URLs.
- Delete a temporary Endpoint when the requested use is complete.
