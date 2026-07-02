# tmux-agent-jump — Design

Date: 2026-07-02
Status: implemented (user was AFK during brainstorming; design chosen autonomously per the
recommended option presented in chat — popup switcher + status-line summary)

## Problem

The user runs one tmux session per project. Each window is split into an agent pane (Claude
Code) on the left and nvim / command panes on the right. With several agents running across
sessions and windows, jumping between them has high friction. Claude Code's built-in agent
view renders the agent inline in the current window, which loses the surrounding
nvim/terminal layout. The user wants a Claude-Code-agent-panel-like list where selecting an
agent jumps to its actual tmux window, preserving that window's layout.

## Reference implementations (both installed locally)

- `hiroppy/tmux-agent-sidebar` (Rust): persistent sidebar pane, hook-fed metadata, heavy
  feature set (worktree lifecycle, notifications, subagent trees). Needs a binary + Claude
  Code plugin hooks.
- `samleeney/tmux-agent-status` (Bash): per-session persistent sidebar + fzf switcher,
  hook-fed, requires modern bash and a collector daemon.

Both are hook-driven and stateful. The core need here — fast jump — does not require
persistent state: an on-demand scan is always fresh and needs zero setup.

## Decision

Pure bash (3.2-compatible) + fzf + tmux built-ins. No hooks, no daemon, no binary,
no state files.

### UX

1. **Popup switcher** — `prefix + a` opens a centered `display-popup` running fzf:
   - one line per agent pane across ALL sessions: status icon + colored status,
     `session:window-index`, git branch of the pane's cwd, and a human title
     (Claude Code sets `pane_title` to the conversation topic; fall back to window name
     when the title is the default `user@host: path` shell title)
   - fzf preview pane on the right shows a live colored snapshot of the selected agent's
     screen (`tmux capture-pane -ep`)
   - Enter or mouse click jumps: `switch-client` to the session, `select-window`,
     `select-pane`. The window's own layout is untouched.
   - `ctrl-r` reloads the list; `esc` closes.
   - Sort order: waiting > busy > idle, then session/window. Current pane is listed too
     (marked), so the popup doubles as a "where am I" overview.
2. **Status-line summary** — appended to `status-right` (opt-out): compact counts like
   `✻2 ▲1 ○3` (busy / waiting / idle). Waiting count is highlighted (yellow) since it
   means an agent is blocked on the user. Empty output when no agents run.

### Detection (zero-config)

- Enumerate panes: `tmux list-panes -a -F ...` (pane id, pid, session, window, title, path).
- One `ps -axo pid=,ppid=,command=` call; awk builds the process tree and walks each pane's
  subtree. A pane is an agent pane if any descendant's executable (first two tokens of the
  command, to catch `node /path/claude/cli.js` and version-named binaries under
  `/.local/share/claude/versions/`) matches the agent regex.
- Default regex: `claude|codex|opencode|aider`. Configurable via `@agent-jump-pattern`.
- Matching only the executable tokens avoids false positives like `nvim CLAUDE.md`.

### Status heuristics (Claude Code screen content)

`tmux capture-pane -p`, last 25 lines:

- **waiting** — permission/confirm dialog: `Do you want`, `Would you like`, `❯ 1. Yes`
- **busy** — `esc to interrupt`, or a spinner line: leading glyph (✻✽✶✳✢·✺) + word + `…`
- **idle** — otherwise

Verified against live panes in the user's environment (working pane showed
`✽ Metamorphosing… (2m 17s · ↓ 6.4k tokens …)`; idle panes show only the `❯` prompt).
Non-Claude agents fall back to idle unless their output happens to match; acceptable for v1.

### Files

```
tmux-agent-jump/
├── agent-jump.tmux           # TPM entry: keybinding + status-right injection
├── scripts/agent-jump.sh     # everything: list | counts | status | picker | popup | jump
└── README.md
```

### Options

| option                  | default                        |
|-------------------------|--------------------------------|
| `@agent-jump-key`       | `a` (prefix table)             |
| `@agent-jump-status`    | `on` (append to status-right)  |
| `@agent-jump-pattern`   | `claude|codex|opencode|aider`  |
| `@agent-jump-width/height` | `90%` / `75%`               |

### Error handling

- No agents found → popup shows a friendly message instead of an empty fzf.
- Panes that die between listing and jump → tmux errors are swallowed; picker can be
  reloaded with ctrl-r.
- `fzf` missing → popup prints install hint.
- status-right injection is idempotent (skips if already present).

### Testing

Scripts are testable headless against the user's live tmux server: `list`, `counts`,
`status` subcommands are pure stdout. Popup interaction verified manually.

## Rejected alternatives

- **Persistent sidebar pane** (like both reference plugins): always-on screen cost,
  needs a refresh daemon, and steals width from the nvim layout the user wants to keep.
- **Hook-based state** (Claude Code hooks writing state files): richer status but requires
  per-machine setup in `~/.claude/settings.json` and goes stale when hooks misfire;
  on-demand capture-pane sniffing is accurate enough and always fresh.
- **tmux native `choose-tree`**: no agent filtering, no status, no live preview styling.

## Addendum (2026-07-02, later): six-state model

User requested the state model match Claude Code's agent view: needs input / failed /
stopped / working / completed / idle, grouped in the picker. Verified against live panes
that all six are detectable from screen content alone (no hooks):

- completed: turn summary line `✻ <Verb>ed for <duration>` (Worked/Churned/Cooked…) or
  `※ recap:` — must exclude lines containing `…`, since working spinner lines like
  `(… · thought for 8s)` also contain "<word> for <n>".
- stopped: `Interrupted` marker Claude Code leaves after esc/ctrl-c.
- failed: `API Error` / rate-limit / timeout / auth error text.
- Resolution: bottom-most matching marker in the last 30 screen lines wins.

Hooks (`Stop`/`StopFailure`/`TaskCompleted`, verified against current hooks docs) were
considered and rejected again: screen heuristics cover all six states with acceptable
fidelity and keep the zero-config design. Picker renders one dim header line per state
group; selecting a header reopens the picker instead of jumping.
