# Contributing

Bug reports, ideas and pull requests are welcome.

## Run it from a checkout

```
swift test
swift build && .build/debug/Broom --preview
```

`--preview` shows the popover with sample data. To try your change against real sessions, build the app with `scripts/make-app.sh` and open `build/Broom.app`. To keep experiments away from your own data, set the `BROOM_*` variables listed in the README.

## What to know before changing things

- **Swift 6, SwiftUI, macOS 14 and later.** Liquid Glass is used on macOS 26 and later, with a drawn fallback before that. The only dependency is GRDB.
- **No network.** Broom makes no outbound connections, and a change that adds one will not be merged.
- **Claude Code's files are read-only.** Nothing under `~/.claude/projects` is ever written. The only write under `~/.claude` is the hooks merge in `settings.json`, after the user has seen the diff and a backup exists.
- **`broom-hook` must never slow Claude Code down.** It exits within 300 ms, always exits 0, and writes nothing to stdout or stderr. Its tests run the real binary.
- **The words are part of the product.** Keep labels short, say each thing once, and name buttons by what they do.
- Swift Testing for tests, one top-level type per file, folders by feature. Every behaviour change comes with a test.

## Pull requests

Keep them small and say what changes for the person using Broom. If the change touches the popover, include a screenshot from `--preview` or `--render`.
