# Security

Broom reads your Claude Code transcripts, can change your Claude Code `settings.json`, listens on a local port and can send signals to Claude Code processes, so security reports are welcome and taken seriously.

## Report a vulnerability

Report it privately: open the [Security tab](https://github.com/mvoshell652/broom/security/advisories/new) and choose **Report a vulnerability**. Please do not open a public issue for a security problem.

Include what you did, what happened, your macOS version and the output of `claude --version`. You can expect a first reply within a week. Fixes ship in a new release, and the release notes credit you unless you ask otherwise.

## What counts

- Anything that lets another process or a web page reach Broom's local listener without the token, or send it events that make Broom act.
- Anything that makes Broom write outside its own folder, write to `settings.json` without the user confirming the change, or signal a process that is not Claude Code.
- Anything that sends data off the Mac.

## How Broom protects you

- The hook listener binds to `127.0.0.1` only and requires a bearer token stored at mode `0600`.
- `settings.json` is changed only through a plan the user has seen as a diff, after a backup is written, and never if the file changed since the plan was made.
- Stop asks for confirmation, checks that the process is still the same Claude Code process, and sends an interrupt. It never sends `SIGKILL`.
- The search index is stored at mode `0600` and holds no tool input or output.

## Supported versions

The latest release.
