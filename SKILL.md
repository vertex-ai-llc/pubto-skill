---
name: pubto-publish
description: Publish and manage local HTTP/HTTPS, WebSocket, TCP, file, directory, and website endpoints through the user's running Pubto Desktop Agent. Use when an AI agent needs to expose a local project, inspect Networks, return a public URL and QR link, stop/delete/rotate an endpoint, or guide the user through Desktop login, Skill installation, and update checks.
---

# Pubto Publish

Use the local `pubto` binary first. It talks only to the loopback Desktop Agent
discovered from the platform discovery record. It never deploys servers, calls a
Relay/Worker directly, or accepts a Control password/token.

The same bundle is distributed from the project source, Pubto Desktop, and the
public repository `https://github.com/vertex-ai-llc/pubto-skill`. A host AI
tool may install it in its own standard user Skill directory. Installation and
updates must be explicit, versioned, atomic, and limited to Pubto-managed
files; never overwrite unrelated user files.

## Install or update from inside an AI CLI

This section is an instruction for the host AI CLI, not a shell command for a
user to paste into a system terminal. When a user supplies the official
installation prompt or asks to install Pubto, use the host's native Skill
installer to fetch only the public repository above. Do not download a Skill
from an arbitrary URL and do not print or request Control, Relay, Worker,
Cloudflare, or application credentials.

On first use, perform these checks in order:

1. Check whether this Skill is already present and read its
   `.pubto-managed.json` marker or version metadata. If the installed version
   is current, continue without downloading it again.
2. If the host supports a native remote-version check, check at most once per
   24 hours unless the user explicitly asks to update. A newer version may be
   installed only after telling the user what will change and receiving
   confirmation. Write to a temporary directory, validate the expected Skill
   files/version, and atomically replace only the old Pubto-managed directory;
   on failure keep the old version.
3. Check `pubto status` and the Agent discovery record. If the CLI or Desktop
   Agent is missing, tell the user exactly what is missing and ask for
   confirmation before using the official Pubto release installer. If Desktop
   is present but stopped, ask the user to start it. If the Agent is not signed
   in, ask the user to finish sign-in in Desktop. Publishing anonymously is not
   allowed.
4. After setup, run `pubto networks`, select a healthy Network, and use the
   normal publishing rules below. The Skill and the Desktop-installed bundle
   use the same CLI/Agent lifecycle for both Simple and CF Networks.

If a user manually copied this file from GitHub, the file itself cannot
silently install an app, CLI, or another Skill. The host AI CLI must perform
the checks above; if it has no native installer, show the official repository
and target directory and ask the user to copy it. Never replace a directory
that lacks the Pubto managed marker.

## Preconditions

1. Detect the Agent without changing the machine:

   ~~~sh
   test -f "$HOME/Library/Application Support/pubto/agent-discovery.json" && cat "$HOME/Library/Application Support/pubto/agent-discovery.json"
   pubto status
   ~~~

   On Linux use the user's XDG config directory (usually $HOME/.config/pubto/agent-discovery.json). On Windows use %AppData%\\pubto\\agent-discovery.json. The record must contain an http loopback URL. Never use a Control URL as the Agent URL.

2. If the Agent is missing, tell the user that publishing requires Pubto Desktop and ask for confirmation before installing or updating it. This project skill does not silently download an installer. After explicit confirmation, use the signed Desktop release flow configured by the host product; verify the SHA-256 manifest, preserve the Agent SQLite state, launch Desktop, then run pubto status and pubto networks again. Do not bypass Gatekeeper, UAC, or package-signature warnings.

3. Check capabilities before selecting a source:

   ~~~sh
   curl --fail --silent http://127.0.0.1:<discovered-port>/v1/capabilities
   ~~~

   The response is authoritative for the running Desktop build. Never publish
   the Agent API itself. A capability being listed does not make an unhealthy
   Network usable; `pubto networks` must also report a live, healthy Network.

## Choose a Network

Run `pubto networks` and select an item whose status is healthy/active. When a
Deployment exposes multiple Networks, pass the selected Network ID explicitly
with `--network-id` (or its `--network` alias). Do not invent a Relay,
Attachment, hostname, or Network ID. The Agent owns Control authentication and
asks Control to choose a healthy Attachment/Relay within the selected Network.

## Publish exactly one source

~~~sh
pubto publish --port 3000 --network-id simple-network-001 --name Frontend --key frontend --duration 30m
pubto publish --url https://127.0.0.1:8443 --network-id simple-network-001
pubto publish --ws-port 8998 --network-id simple-network-001
pubto publish --tcp 5432 --network-id simple-network-001
pubto publish --file ./report.docx --network-id simple-network-001
pubto publish --dir ./documents --network-id simple-network-001
pubto publish --website ./dist --network-id simple-network-001
~~~

Pass exactly one of `--port`, `--ws-port`, `--tcp`, `--url`, `--file`, `--dir`,
`--website`, or `--kind/--target`. Ask before publishing databases, SSH,
caches, admin panels, LAN targets, or public Internet targets. Prefer a short
duration for temporary or sensitive endpoints.

Publishing is idempotent. The CLI derives a stable clientKey from protocol, target, and Network. For a logical endpoint that may move ports, provide an explicit stable --key (for example frontend); repeating the same Project and key updates/reuses the same endpointId and slug. Use --new only when the user asks for a new public address. The CLI treats a different endpointId returned for an existing key as an idempotency failure and removes only the duplicate produced by that request.

A successful response contains `endpointId`, the canonical 16-character slug,
`publicUrl`, Network metadata, Control publication identifiers, and expiry
fields when present. `controlGrantId` is an authorization grant, not an
Attachment ID; do not relabel it as `attachmentId`. The loopback Entry response
does not expose the private Attachment ID. Simple and CF use this exact same
CLI and Agent lifecycle; `networkKind` is output metadata, not a client-side
transport switch.

For TCP, `publicUrl` is the canonical `tcp://` address returned by Control.
Return and accept that exact `tcp://` address for user-facing TCP operations;
do not rewrite it to `https://`, a Relay/Gateway address, or a `/tcp` URL. The
Desktop Agent may use WSS internally to bridge the byte stream to a local TCP
mapping, but that implementation detail is not a replacement public address.

After publishing, read `pubto list` until the endpoint is running and has a
non-empty `publicUrl`. Report the exact URL, Network, returned Control
identifiers, and expiry. Verify the address with a read-only,
protocol-appropriate request. For TCP, preserve the returned `tcp://` address
and verify the Desktop mapping rather than opening it in a browser. Do not
claim success from a local Agent 2xx alone if the endpoint has no public URL or
is unreachable.

## Lifecycle operations

~~~sh
pubto list
pubto status
pubto start --endpoint <endpoint-id>
pubto stop --endpoint <endpoint-id>
pubto rotate --endpoint <endpoint-id>
pubto delete --endpoint <endpoint-id>
pubto remark --endpoint <endpoint-id> --text "Review build"
pubto remark --endpoint <endpoint-id> --clear
~~~

Use the returned `endpointId`, not the slug or URL, for later actions. `stop`
pauses traffic while retaining the endpoint; `delete` revokes it and should
make the old address return 404; `rotate` keeps the logical endpoint but
replaces its public address. Treat delete/rotate as destructive and confirm
when the endpoint is not clearly temporary. Remarks are public metadata and
must not contain credentials, tokens, private paths, or internal notes.

For a multi-endpoint handoff, use the Desktop Collection/Homepage feature; a Collection is a page of existing Endpoint links, not another transport or a second publish operation.

## Login and QR handoff

The Agent owns account authentication. Do not ask an AI agent to store or print Control passwords. Check pubto status for accountAuthenticated; if false, direct the user to the running Desktop login screen and wait for them to finish. The loopback account routes are available to the Desktop UI:

~~~text
GET  /v1/account
POST /v1/account/code       {"email":"user@example.com"}
POST /v1/account/verify     {"email":"user@example.com","code":"123456"}
POST /v1/account/login      {"email":"user@example.com","password":"..."}
POST /v1/account/logout
~~~

Only send a password when the user explicitly supplies it; prefer the email-code flow. Never expose the code or password in logs. After login, rerun pubto networks before publishing.

When a successful HTTP/WebSocket publish returns publicUrl, show it as a normal
link and as a QR value using the host's QR renderer (for example, the Desktop
QR dialog). The QR value is exactly the returned URL; do not put passwords,
Control tokens, or Agent URLs in a QR code. TCP returns its exact `tcp://`
canonical address and is consumed through Desktop mapping; do not present it as
a browser link or QR handoff. If the host cannot render QR, tell the user to
open the Desktop endpoint dialog rather than using an untrusted QR service.

## Desktop detection and update

`GET /v1/daemon/status` reports Agent PID, loopback URL, uptime, and
connection state; `GET /v1/capabilities` reports the Agent version and
supported transports. Use those read-only routes plus the host product's
signed release manifest to detect an outdated Desktop. Ask before installing
an update. An update must verify the manifest checksum, preserve local SQLite
and Control configuration, launch the new Desktop, and confirm `/v1/health`
and `/v1/daemon/status`; roll back if the Agent is unhealthy. This Skill only
documents the decision flow; the host installer supplies the platform-specific
signed artifact. It must not download an arbitrary binary or run a package
installer on the user's behalf.

## Browser and protocol checks

HTTP 200 from a public URL does not prove browser CORS compatibility. For
browser APIs, check the source's explicit Origin/CSRF policy. WebSocket
upgrades require a successful 101 and an allowed source Origin; CORS headers
alone do not authorize an upgrade. TCP has a public `tcp://` canonical address
and is not a browser URL. The Desktop-to-Desktop WSS bridge is an internal
transport detail; never make the Agent or Relay reflect arbitrary Origins or
add wildcard credentialed CORS.

## Failure handling

- If `pubto status` cannot discover the Agent, stop and ask for Desktop
  installation/startup; do not call Control directly.
- If pubto networks is stale/unavailable, report the Control connection state and do not fabricate a Network.
- If publish returns an Agent error, preserve its HTTP status/message and retry only idempotent operations.
- If a repeated publish returns a different endpoint ID for the same explicit key, treat it as an idempotency failure and stop rather than creating more endpoints.
- Delete temporary endpoints when the requested handoff is complete.
