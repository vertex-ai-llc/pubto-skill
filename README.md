# Pubto Skill

`pubto-publish` lets a supported AI CLI publish an explicitly approved local
HTTP, HTTPS, WebSocket, TCP, file, directory, or website target through the
user's signed-in Pubto Desktop.

## Quick install prompt

Paste this one line into your AI CLI's native Skill installer:

```text
Install or update the official Pubto Skill from https://github.com/vertex-ai-llc/pubto-skill.
```

The host AI CLI applies the installation and update rules in `SKILL.md`. The
Skill checks the local command, Desktop, login state, and managed version
before publishing; it never grants anonymous access or handles provider or
application credentials.

## Install paths

All paths install the same versioned Skill and use the same Pubto command and
Desktop:

1. **Install from Desktop:** open **With AI** and install the detected integration.
2. **Ask your AI CLI:** paste the one-line prompt above. The host's native Skill
   installer downloads this repository and asks before installing a missing
   Desktop or command.
3. **Copy from GitHub:** copy this repository's `pubto-publish` directory into the AI CLI's standard
   user Skill directory. On first use the Skill checks the command, Desktop and
   login state, and asks before completing the official installation flow.

The AI CLI may check for a newer Skill once per 24 hours. Updates are staged,
verified, and atomic; a failed update keeps the previous version. Do not copy
over a directory that is not marked as Pubto-managed.

Skill installation never grants anonymous access. The user must sign in with
Pubto Desktop before publishing. The Skill never receives or prints provider,
database, or application credentials.

Once `pubto` is installed, Desktop upgrades are performed with
`pubto update check` followed by `pubto update apply --yes` after confirmation.
The bundled `install-desktop.sh`/`install-desktop.ps1` scripts are only the
bootstrap fallback when the command and Desktop are missing.

See [`SKILL.md`](SKILL.md) for the publishing contract and [`VERSION`](VERSION)
for the bundle version.
