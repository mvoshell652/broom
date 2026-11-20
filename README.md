# Broom

[![tests](https://github.com/mvoshell652/broom/actions/workflows/ci.yml/badge.svg)](https://github.com/mvoshell652/broom/actions/workflows/ci.yml) [![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE) ![macOS 15.6+](https://img.shields.io/badge/macOS-15.6%2B-lightgrey)

Broom is a menu bar app for Claude Code. It finds the chats you started more than once, the ones left hanging and the ones gone quiet, and helps you tidy them. It also shows which open session is waiting on you, which are still working and which have finished, and takes you straight to the one that needs you.

https://github.com/user-attachments/assets/c993a525-4387-41c3-870d-58e76d571415

The broom in the menu bar shows how many sessions are running, and gets an amber dot when one is waiting on you. That is usually all you need to see: no dot, nothing needs you.

<img src="docs/tour/menu-bar.png" width="216" alt="Four states of the menu bar item: the broom alone, the broom with 2, the broom with 2 and an amber dot, and the broom with 12 and an amber dot.">

Click it and a popover opens on the Inbox, with a search field and three tabs: Inbox, Live and History.

## Why

Broom started in a LinkedIn thread. A product designer wished Claude had a "clean up time": a way to sort stray chats and catch the ones she had started more than once. A design leader added the other half. With four to six chats open, he kept losing track of which were long-running agent loops and which were quick questions. I had both problems, so I said I would build something.

Those two complaints became Broom's two halves: the **Inbox** for the chats piling up, and **Live** for the sessions open right now.

## Install

```
d=$(mktemp -d) && git clone --depth 1 https://github.com/mvoshell652/broom "$d" && sh "$d/install.sh"
```

You need macOS Sequoia 15.6 or later, Claude Code, and Apple's Command Line Tools 26 or later. Install the tools with `xcode-select --install`. Broom itself runs on macOS 14, but the version 26 tools that build it need 15.6. The script builds Broom on your Mac, copies it to `/Applications` (or `~/Applications` when that is not writable) and opens it. Free and open source.

Then connect Claude Code, so a waiting session shows right away and can notify you:

1. Click the broom in the menu bar, then the gear.
2. Choose **Connect Claude Code…**.
3. Read the change Broom will make to `~/.claude/settings.json` and confirm. Broom saves a backup next to the file first and leaves your other hooks alone.

Broom works without this step too, from the session transcripts, a little slower and without waiting notifications.

**Update:** run the install line again. Your settings, search index and history are kept.

**Uninstall:** choose **Disconnect…** in Broom's settings to take its hooks out of `settings.json`, quit Broom, then:

```
rm -rf /Applications/Broom.app ~/Library/Application\ Support/Broom
```

## A tour

### Inbox: the chats piling up

Broom reads your past Claude Code chats and raises the few worth a decision:

<img src="docs/tour/inbox.png" width="480" alt="The Inbox. Possible duplicates: you have started 3 chats about Supabase RLS policies for teams since Oct 22, with Review and merge and Not the same. Open loops: one chat ended on a question, one on I will do this tomorrow. Quiet for 3 months: mobile, 2 chats, with Archive.">

Duplicates are chats from the last 30 days that open with the same or a very similar prompt. **Review & merge** folds them into one row, newest on top, and **Not the same** is remembered. An open loop comes back if its chat picks up again, and an archived project stays in search.

**Sweep now** goes through the same items one card at a time, like a weekly review: merge, archive or reopen, or skip a card until next week.

<img src="docs/tour/sweep.png" width="480" alt="The weekly sweep at card 1 of 4: Merge duplicates, 3 chats about Supabase RLS policies for teams, listed with their dates, a note that nothing gets deleted and merges can be undone for 30 days, and the buttons Skip, Edit and Merge.">

### Live: the sessions open right now

Every Claude Code session on your Mac, from any terminal, your editor or the Claude desktop app, sorted by what it needs from you:

<img src="docs/tour/live.png" width="480" alt="The Live tab. Waiting on you: Store directory, Texas batch, asking whether to add 42 stores or review 9 first, paused 6 minutes ago, with Open chat and Snooze 1h. Running: Scraper backfill at step 6 of 9 with a progress bar, two more sessions, and a scheduled task. Done since you looked: Menu bar app design notes, finished 4 minutes ago.">

A finished session leaves Done once you have seen it. Further down, quick chats (one question, no tools) fade after a day, and sessions idle for two hours or Claude Code processes with no session each get **Stop**. **Stop all agents** in the footer interrupts every running or waiting session after you confirm, like pressing Control-C, never a force quit.

### History

Every merge, archive and "done" from the last 30 days, grouped by day. Open a row to see the chats it touched.

<img src="docs/tour/history.png" width="480" alt="History: last swept 6 days ago. Today: Marked Send vendor follow-ups done, and Merged 2 chats in mobile. Yesterday: Archived 2 chats in api-server. Each row shows its time.">

### Search

Press ⌥⌘B anywhere, or type in the popover's search field, to find any past chat by what you typed or what Claude replied. It matches the words, and the meaning when you remember the idea but not the words. Open a result to resume the chat, or copy the command that resumes it.

<img src="docs/tour/search.png" width="480" alt="Search for search ranking weights in the popover, listing four past chats with their project, a line from the conversation and the date, and the hints Return to open and Command-C to copy the resume command.">

### Notifications and settings

Broom notifies you when a session is waiting on you, with **Open** and **Snooze 1h** on the notification. It can notify you when a session finishes too; that one is off until you turn it on. Settings also has opening at login, which terminal ended sessions reopen in, the Claude Code connection, and your search index.

## Questions

**Does anything leave my Mac?** No. Broom makes no network connections. Search runs on a local copy of what you typed and what Claude replied, at mode `0600` in `~/Library/Application Support/Broom`, without tool input or output, and matching by meaning uses Apple's on-device sentence embeddings. **Delete Index** in settings removes the copy.

**Will it touch my Claude Code files?** It reads the transcripts in `~/.claude/projects` and never writes there. The only file it changes is `settings.json`, and only after you confirm the diff. Merging and archiving change how Broom shows your chats, not the chats.

**Which terminals does Open chat work with?** A running session is brought forward in whatever app it runs in, including the Claude desktop app. To reopen an ended session, Broom uses Terminal, iTerm, Ghostty, Warp, Visual Studio Code or Cursor; pick one in settings.

**Does it see chats on claude.ai?** Not yet. Broom follows Claude Code sessions only.

**Why build from source instead of downloading an app?** The project has no Apple Developer ID yet, so a downloaded app could not be notarized and macOS would warn on every install. Building on your own Mac avoids that.

**How heavy is it?** Measured with 23 sessions tracked: under 1% CPU when idle and under 70 MB of memory.

## How it works

Claude Code runs a small helper, `broom-hook`, for each hook event: a session starting, a prompt, a tool call, a permission request, a stop. The helper passes the event to Broom over `127.0.0.1` with a private token, then exits within 300 ms whether or not Broom is running, and never prints to your terminal. Broom turns the events into each session's state, reads the transcript for the title and the task list, and checks that the session's process is still alive. A session without hooks has its state worked out from the transcript alone.

## Keys

| Where | Key | Does |
|---|---|---|
| Anywhere | ⌥⌘B | Opens search |
| Popover | ↑ ↓ | Moves between sessions |
| Popover | Return | Opens the selected session |
| Popover | ⌘. | Stops the selected session, after you confirm |
| Sweep | ← → E | Skips a card, does its action, edits it |

## Develop

```
scripts/test.sh
swift build && .build/debug/Broom --preview
scripts/make-app.sh
```

`--preview` opens the popover with sample data in a window; add `--tab live` or `--tab history`, `--dark`, or `--deck` for the sweep. `--render <folder>` writes PNGs of every screen. These variables point Broom away from your real data, so experiments never touch it:

| Variable | Replaces |
|---|---|
| `BROOM_PROJECTS_DIR` | `~/.claude/projects` |
| `BROOM_SETTINGS_FILE` | `~/.claude/settings.json` |
| `BROOM_SUPPORT_DIR` | `~/Library/Application Support/Broom` |
| `BROOM_DATABASE`, `BROOM_INDEX`, `BROOM_WORKSTREAMS` | The session, search and organiser databases in it |
| `BROOM_HOOK_PORT` | Port 47811 |
| `BROOM_NO_NOTIFICATIONS` | Set to `1` to post none |

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, and report security problems privately as [SECURITY.md](SECURITY.md) describes.

## Status

Version 0.1, early. Bug reports and ideas are welcome in [Issues](https://github.com/mvoshell652/broom/issues).

## License

MIT. See [LICENSE](LICENSE).
