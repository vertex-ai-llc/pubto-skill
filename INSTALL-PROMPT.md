# Install Pubto in an AI CLI

Copy the prompt below into the AI CLI you want to use. It is an instruction
for that AI CLI's native Skill installer, not a command to paste into a system
terminal.

```text
Install or update the official Pubto Skill from https://github.com/vertex-ai-llc/pubto-skill.

Use your native Skill installer and install only the pubto-publish Skill in
this tool's standard user Skill directory. If it is already installed, read
the Pubto managed marker or VERSION metadata. Check the remote version at most
once every 24 hours unless I explicitly ask for an update. Update only when a
newer version is available, after telling me what will change and asking for
confirmation. Stage the download, verify the expected Pubto files and
checksum when available, then atomically replace only the existing
Pubto-managed Skill. If anything fails, keep the working version. Do not
overwrite unrelated user files.

Before the first publish, check whether the official Pubto CLI and local
Pubto Desktop Agent are available. If either is missing, tell me exactly what
is missing and ask for confirmation before downloading or installing the
official Pubto Desktop package or bundled CLI from https://pubto.dev/downloads.
Do not use another source, run an unapproved installer, print credentials, or
ask for Control, Relay, Gateway, Cloudflare, database, or application secrets.

After setup, run the equivalent of `pubto status` and `pubto networks`. If
Desktop is installed but stopped, ask me to start it. If the Agent reports
that the account is not authenticated, ask me to sign in through Pubto
Desktop. Anonymous publishing is not allowed.

Once setup is complete, use the Pubto Skill and the local CLI to publish only
the target I approve, with an explicit protocol and expiry. Verify the result
and return the exact public URL or the exact tcp:// address. Do not rewrite a
TCP address as HTTPS or expose the local Agent address.
```

The prompt is intentionally idempotent: installing it again must not create a
second Skill or a second CLI. A manually copied Skill cannot install software
by itself; on first use the host AI CLI performs the checks and asks for the
same confirmation before invoking the official installer.
