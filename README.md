# tmux-agent-jump

Jump to any AI agent pane across all your tmux sessions — one keystroke, one picker,
zero configuration.

```
┌────────────────────────── ✻ agents ───────────────────────────┐
│  enter jump · ctrl-r refresh · esc close        ┌─────────────┤
│                                                 │             │
│▌ ▲ needs you  proj-a:1   fix login bug     ⎇ fix│  (live view │
│  ✻ working    proj-b:0   refactor api      ⎇ ma…│   of the    │
│  ✻ working    proj-b:2   write e2e tests   ⎇ te…│   selected  │
│  ○ idle       proj-c:1   migrate db schema ⎇ ma…│   agent's   │
│◂ ○ idle       proj-c:3   …                      │   screen)   │
│                                                 │             │
└─────────────────────────────────────────────────┴─────────────┘
```

You run one tmux session per project, each window split into an agent pane plus
nvim/shell panes. `prefix + a` pops up a picker of every agent pane in every session —
with live status, git branch, conversation topic, and a live preview of its screen.
Press enter (or click) and tmux switches session → window → pane. Your window layouts
stay exactly as they were.

## Why not a sidebar?

Plugins like [tmux-agent-sidebar](https://github.com/hiroppy/tmux-agent-sidebar) and
[tmux-agent-status](https://github.com/samleeney/tmux-agent-status) keep a persistent
sidebar pane fed by agent hooks. tmux-agent-jump takes the opposite approach:

- **No hooks, no daemon, no binary, no state.** A single bash script scans panes
  on demand — the picker is always live, and there is nothing to set up or go stale.
- **Zero screen cost.** Nothing is docked; your layout is yours.
- **macOS system bash is enough** (bash 3.2 compatible).

## Features

- **All sessions, one picker** — every pane running Claude Code / Codex / OpenCode /
  aider, sorted so agents that need you come first
- **Live status** — `▲ needs you` (waiting on a permission prompt), `✻ working`,
  `○ idle`, detected from the pane's actual screen content
- **Live preview** — the right half of the picker shows the selected agent's screen,
  in color, as it is right now
- **Context at a glance** — conversation topic (from the pane title Claude Code sets),
  git branch of the pane's cwd, working directory; `◂` marks where you came from
- **Status-line summary** — `▲1 ✻2 ○3` in `status-right`; the yellow `▲` tells you an
  agent is blocked on you without opening anything

## Requirements

- tmux ≥ 3.2 (popups) — 3.3+ recommended for rounded borders
- [fzf](https://github.com/junegunn/fzf)

## Install

With [TPM](https://github.com/tmux-plugins/tpm):

```tmux
set -g @plugin 'peixiangluo/tmux-agent-jump'
```

Or manually — clone anywhere and add to `~/.tmux.conf`:

```tmux
run-shell /path/to/tmux-agent-jump/agent-jump.tmux
```

Reload tmux (`tmux source ~/.tmux.conf`), then press `prefix + a`.

## Options

Set in `~/.tmux.conf` before the plugin line:

| option | default | description |
|---|---|---|
| `@agent-jump-key` | `a` | key after prefix that opens the picker |
| `@agent-jump-status` | `on` | prepend the agent summary to `status-right` |
| `@agent-jump-pattern` | `claude\|codex\|opencode\|aider` | regex matched against pane child processes |
| `@agent-jump-width` | `90%` | popup width |
| `@agent-jump-height` | `75%` | popup height |

Example:

```tmux
set -g @agent-jump-key 'g'
set -g @agent-jump-status 'off'
set -g @agent-jump-pattern 'claude|goose'
```

## Keys inside the picker

| key | action |
|---|---|
| `enter` / mouse click | jump to the agent's window & pane |
| `ctrl-r` | refresh the list |
| `esc` | close |
| type anything | fuzzy-filter by session, topic, branch, path |

## How it works

1. `tmux list-panes -a` + one `ps` call; a pane is an agent pane if any process in its
   subtree matches the agent pattern (matched against the executable, so editing
   `CLAUDE.md` in nvim doesn't count).
2. Status comes from `tmux capture-pane`: a permission prompt (`Do you want …`) means
   **needs you**, a spinner line / `esc to interrupt` means **working**, otherwise idle.
3. Jumping is plain `switch-client` + `select-window` + `select-pane`.

Status heuristics are tuned for Claude Code; other agents are detected and listed but
may always show as idle.

## License

MIT
