---
name: pubto-publish
description: Publish, inspect, verify, edit, expire, stop, rotate, and remove independent local HTTP/HTTPS, WS/WSS, directory, file, or TCP endpoints through a running Pubto Desktop Agent. Use when an AI needs to create a public preview, expose a local API or database, choose a Relay, map a remote Pubto endpoint back to localhost, or diagnose an unavailable publication.
---

# Pubto Publish

Use the loopback Agent API at `http://127.0.0.1:8788`. Never publish the Agent API itself.

## Model

- A project is a name-only folder.
- An endpoint is one publication: one random 16-character slug, one target, one protocol, one Relay, and independent lifecycle/access settings.
- Creating an endpoint publishes it immediately. Do not issue a second project-level publish action.
- `http` targets may use `http://` or `https://`; `websocket` targets may use `ws://` or `wss://`; PostgreSQL, MySQL, Redis, SSH, MQTT, and other byte streams use `tcp`.
- A `directory` target may be a folder or one file. A folder renders a safe file listing and never executes `index.html` automatically; use an `http` target pointed at a locally started web server for website behavior. Files over `maxFileBytes` (default 1 MiB) return 413.

## Publish workflow

1. Call `GET /v1/health`, `GET /v1/capabilities`, and `GET /v1/relays`.
2. Reuse a matching project or create a folder with `POST /v1/projects` and `{"name":"..."}`.
3. Create exactly one endpoint with `POST /v1/projects/{projectId}/entries` and `name`, `kind`, `target`, and `relayId`.
4. Re-read `GET /v1/projects` until that endpoint reports `running`, `publicUrl`, and its `reachable` state.
5. Verify with a read-only protocol-appropriate request. Never send application credentials during a probe.
6. Apply optional password or duration only after creation. Use a 30-minute expiry by default for an explicitly temporary preview.
7. Report the exact public address. Delete the endpoint when the requested temporary use is complete.

## Endpoint operations

```text
PUT    /v1/projects/{projectId}/entries/{entryId}                  edit name, kind, target, relayId
DELETE /v1/projects/{projectId}/entries/{entryId}                  revoke and delete; old address becomes 404
POST   /v1/projects/{projectId}/entries/{entryId}/start|stop       independent lifecycle
PUT    /v1/projects/{projectId}/entries/{entryId}/expiration       {"expiresAt":"RFC3339"} or empty
PUT    /v1/projects/{projectId}/entries/{entryId}/password         {"password":"..."} or empty
POST   /v1/projects/{projectId}/entries/{entryId}/rotate-address   old address becomes 404 immediately
POST   /v1/projects/{projectId}/entries/{entryId}/report           {"reason":"..."}
```

Changing a password invalidates old passwords and cookies immediately. Password plaintext is sent only to the loopback Agent, which stores a salted digest; Relay and Control never receive it.

## Other APIs

- Projects: `POST /v1/projects`, `PUT /v1/projects/{id}`, `DELETE /v1/projects/{id}`. Project deletion removes every endpoint after explicit confirmation.
- Local mappings: `GET|POST /v1/bindings`, then `PUT|DELETE /v1/bindings/{id}` or `POST /v1/bindings/{id}/start|stop|test`.
- Relay profiles: `GET|POST /v1/relays`, then `PUT|DELETE /v1/relays/{id}` or `POST /v1/relays/{id}/test`. An endpoint may be moved between profiles with its edit operation.
- Agent: `GET /v1/daemon/status`, `POST /v1/daemon/restart`, `POST /v1/daemon/stop`.

## Safety

- Ask for confirmation before publishing databases, caches, SSH, admin panels, LAN targets, or public Internet targets.
- Prefer a 30-minute expiry for sensitive temporary endpoints.
- Never print Relay, Control, Cloudflare, database, or application secrets.
- Treat TCP public addresses as raw sockets, not browser URLs.
- Deleting or rotating must not redirect or reuse the old address.

Use [scripts/pubtoctl.sh](scripts/pubtoctl.sh) for deterministic basic operations.
