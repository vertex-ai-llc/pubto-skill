---
name: pubto-publish
description: Publish, share, expose, preview, forward, or map local HTTP/HTTPS, WebSocket, TCP, file, folder, and website targets. Use for requests such as 发布、共享、公开本地服务、内网穿透、端口映射、预览文件/网站、查看公开地址、停止/删除/更换地址, or equivalent English requests involving localhost, ports, URLs, files, directories, APIs, databases, or AI Skill setup.
---

# Pubto Publish

## User-facing response rules

Keep implementation details out of the conversation. Do not mention Agent,
Control, Relay, Worker, Durable Object, KV, loopback, discovery files,
internal ports, attachment IDs, route epochs, or private network IDs. Perform
those checks silently and describe only the useful result in product language.
Never print a local target address when the user needs the shareable address.
Always print the complete returned public address as plain text in a
copy-friendly line, even when also providing a markdown link:

~~~text
Public address: https://the-complete-address.example
~~~

For TCP, print the complete `tcp://` address exactly as returned. Include a
short expiry and verification result, but omit internal identifiers and local
IP/port details unless the user explicitly asks for them.

Use the local `pubto` binary first. It talks to the signed-in Pubto Desktop
runtime and never deploys servers or asks for infrastructure credentials.

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
from an arbitrary URL and do not print or request infrastructure, provider,
or application credentials.

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
3. Check `pubto status` silently. If the CLI or Desktop runtime is missing
   while the user has already requested a publish, ask once for permission to
   install the official Desktop package (the package includes the matching
   CLI and local runtime). On Windows, use the bundled
   `scripts/install-desktop.ps1 -Yes` bootstrap flow after confirmation; it
   installs both Desktop and the matching `pubto` command and configures the
   user's command path. Do not launch only the raw package when the bootstrap
   flow is available. Complete and verify that setup before asking which target
   to publish. Do not ask for the target twice. If Desktop is stopped or signed
   out, ask the user to open it and finish sign-in. Publishing anonymously is
   not allowed.
4. After setup, run `pubto networks`, select a healthy option, and use the
   normal publishing rules below. Both supported network options use the same
   publishing workflow.

### Windows installation confirmation

When the official Windows installer is opened from the Skill, Windows may
show a security confirmation before it starts. Confirm that the download came
from `https://pubto.dev/downloads` and that the window identifies **Pubto**.
Then choose **More info** and **Run anyway**, followed by **Yes** on the normal
Windows permission prompt. If the window names a different application or the
download did not come from the official Pubto downloads page, stop and report
it instead of continuing. After installation, start a new terminal (or
restart the AI CLI) so it can see the newly installed `pubto` command.

Do not show this instruction unless the installer actually triggers that
confirmation.
It is only a fallback for the platform confirmation that can appear while the
official package is being opened.

If the signed-in account has no Project yet, the first `pubto publish` creates
one named `Default` automatically. This is an explicit CLI behavior; do
not ask the user to open an extra project-management screen just to publish.
Use `--project "Name"` or `--project-id ID` when the user has asked for a
specific existing Project.

If a user manually copied this file from GitHub, the file itself cannot
silently install an app, CLI, or another Skill. The host AI CLI must perform
the checks above; if it has no native installer, show the official repository
and target directory and ask the user to copy it. Never replace a directory
that lacks the Pubto managed marker.

## Preconditions

1. Check the local Pubto runtime without changing the machine by running
   `pubto status` silently. The CLI performs local discovery itself. Never
   read, print, or ask the user to copy a discovery file, loopback URL, local
   port, or an internal environment override.

2. If the local Pubto runtime is missing, tell the user that publishing
   requires Pubto Desktop and ask for confirmation before installing or
   updating it. This Skill does not silently download an installer. After
   explicit confirmation, use the official Desktop release flow configured by
   the host product; verify its checksum, preserve account and endpoint data,
   launch Desktop, then run `pubto status` and `pubto networks` again. Do not
   bypass platform protections blindly; use the Windows installation guidance
   above only for the official package.

3. Check Desktop readiness before selecting a source:

   ~~~sh
   pubto status
   ~~~

   The response confirms that the installed Desktop is ready. Never publish
   the local management interface itself. `pubto networks` must also report a
   live, healthy option for the requested protocol.

## Choose a Network

Run `pubto networks` and select an item whose status is healthy/active. When
more than one healthy option is available, select one internally or ask the
user only when the choice affects the requested outcome. Do not invent a
network, hostname, or infrastructure address.

## Publish exactly one source

~~~sh
pubto publish --port 3000 --network-id simple-network-001 --name Frontend --key frontend --duration 30m
pubto publish --url http://127.0.0.1:8443 --network-id simple-network-001
pubto publish --ws-port 8998 --network-id simple-network-001
pubto publish --tcp 5432 --network-id simple-network-001
pubto publish --file ./report.docx --network-id simple-network-001
pubto publish --dir ./documents --network-id simple-network-001
pubto publish --website ./dist --network-id simple-network-001
~~~

Before publishing, inspect the request and project for candidate services or
paths. If there are multiple plausible targets, ask which human-readable
service or file the user means (or whether all should be published). Do not
print a port scan, local address, process list, discovery path, or management
URL. Never silently choose the first target when the user has not identified
one.

Also inspect the selected web app's configuration and recent output for
references to other local services, such as an API, WebSocket endpoint,
callback server, preview server, or database port. A page published by itself
may still fail when it calls those other ports. Explain the dependency in
plain language and offer to publish the related ports together so teammates
can test the complete flow. Ask separately before exposing a database,
admin panel, cache, or other sensitive service; never publish such a target
just because the web app references it.

Pass exactly one of `--port`, `--ws-port`, `--tcp`, `--url`, `--file`, `--dir`,
`--website`, or `--kind/--target`. Ask before publishing databases, SSH,
caches, admin panels, LAN targets, or public Internet targets. Prefer a short
duration for temporary or sensitive endpoints.

Publishing is idempotent. The CLI derives a stable clientKey from protocol, target, and Network. For a logical endpoint that may move ports, provide an explicit stable --key (for example frontend); repeating the same Project and key updates/reuses the same endpointId and slug. Use --new only when the user asks for a new public address. The CLI treats a different endpointId returned for an existing key as an idempotency failure and removes only the duplicate produced by that request.

A successful response contains a canonical slug, `publicUrl`, and expiry
fields when present. Treat the remaining identifiers as internal bookkeeping;
do not repeat them to the user. Both supported network options use the same
CLI workflow and the selected option is an implementation detail, not a
separate user protocol.

For TCP, `publicUrl` is the canonical `tcp://` address returned by Pubto.
Return and accept that exact `tcp://` address for user-facing TCP operations;
do not rewrite it to `https://` or add a path. Pubto may use a secure internal
bridge for the local mapping, but that implementation detail is not a
replacement public address.

After publishing, read `pubto list` until the endpoint is running and has a
non-empty `publicUrl`. Report the complete public URL as plain text, its
protocol, expiry, and a protocol-appropriate verification result. For TCP,
preserve the returned `tcp://` address and verify the local mapping rather
than opening it in a browser. Do not claim success unless the public address
exists and is reachable.

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

Pubto owns account authentication. Do not ask an AI agent to store or print
infrastructure passwords. Check `pubto status` for an authenticated account;
if false, direct the user to the Pubto Desktop sign-in screen and wait for
them to finish. The local account routes are available to the Desktop UI:

~~~text
GET  /v1/account
POST /v1/account/code       {"email":"user@example.com"}
POST /v1/account/verify     {"email":"user@example.com","code":"123456"}
POST /v1/account/login      {"email":"user@example.com","password":"..."}
POST /v1/account/logout
~~~

Only send a password when the user explicitly supplies it; prefer the email-code flow. Never expose the code or password in logs. After login, rerun pubto networks before publishing.

When a successful HTTP/WebSocket publish returns `publicUrl`, show the full
address in plain text and, when available, as a normal link and QR value using
the host's QR renderer. The QR value is exactly the returned URL; do not put
passwords or local management addresses in a QR code. TCP returns its exact
`tcp://` address and is consumed through local mapping; do not present it as a
browser link or QR handoff.

## Desktop detection and update

Use `pubto update check` to detect an outdated Desktop when the managed CLI is
already installed. After the user confirms, run `pubto update apply --yes`;
the CLI invokes the same official, transactional installer used by the
bootstrap flow, verifies its checksum, preserves local account and endpoint
data, restarts Desktop, and confirms that its local runtime is ready. A failed
upgrade rolls back to the previous app and data. Do not execute
`install-desktop.sh` or `install-desktop.ps1` for an upgrade when `pubto` is
available: those scripts are bootstrap fallbacks for a missing CLI/Desktop.
Never download an arbitrary binary or run an unapproved package installer.

## Browser and protocol checks

HTTP 200 from a public URL does not prove browser CORS compatibility. For
browser APIs, check the source's explicit Origin/CSRF policy. WebSocket
upgrades require a successful 101 and an allowed source Origin; CORS headers
alone do not authorize an upgrade. TCP has a public `tcp://` canonical address
and is not a browser URL. Internal bridging must never reflect arbitrary
Origins or add wildcard credentialed CORS.

## Failure handling

- If `pubto status` cannot reach the local Pubto runtime, stop and ask for
  Desktop installation/startup; do not call infrastructure services directly.
- If `pubto networks` is stale/unavailable, report that publishing options
  are temporarily unavailable and do not fabricate one.
- If `pubto status` confirms that Desktop is ready but a local command still
  cannot reach it, or Desktop functions repeatedly fail, check for a VPN,
  proxy, firewall, or security filter intercepting local application traffic.
  Ask the user to allow Pubto Desktop and `pubto` local communication or to
  temporarily pause that software and retry. Never change system proxy/VPN
  settings automatically, and do not print a local address or port. Show this
  hint only after the healthy status check and a real local operation failure;
  do not suggest it for an ordinary sign-in, quota, or public-network error.
- If publish returns a local runtime error, preserve its HTTP status/message and retry only idempotent operations.
- If a repeated publish returns a different endpoint ID for the same explicit key, treat it as an idempotency failure and stop rather than creating more endpoints.
- Delete temporary endpoints when the requested handoff is complete.
