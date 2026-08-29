# Pubto Skill

`pubto-publish` lets a supported AI CLI publish an explicitly approved local
HTTP, HTTPS, WebSocket, TCP, file, directory, or website target through the
user's signed-in Pubto Desktop Agent.

## Install paths

All paths install the same versioned Skill and use the same Pubto CLI and
Desktop Agent:

1. **Install from Desktop:** open **With AI** and install the detected integration.
2. **Ask your AI CLI:** paste [`INSTALL-PROMPT.md`](INSTALL-PROMPT.md). The host's
   native Skill installer downloads this repository and asks before installing
   a missing Desktop or CLI.
3. **Copy from GitHub:** copy this repository's `pubto-publish` directory into the AI CLI's standard
   user Skill directory. On first use the Skill checks the CLI, Agent and
   login state, and asks before completing the official installation flow.

The AI CLI may check for a newer Skill once per 24 hours. Updates are staged,
verified, and atomic; a failed update keeps the previous version. Do not copy
over a directory that is not marked as Pubto-managed.

Skill installation never grants anonymous access. The user must sign in with
Pubto Desktop before publishing. The Skill never receives or prints Control,
Relay, Gateway, Cloudflare, database, or application credentials.

See [`SKILL.md`](SKILL.md) for the publishing contract and [`VERSION`](VERSION)
for the bundle version.
