#!/usr/bin/env bash
# tmux-agent-jump — list AI agent panes across all tmux sessions and jump to them.
# bash 3.2 compatible (macOS system bash). No daemon, no state, no hooks.

set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

DEFAULT_PATTERN='claude|codex|opencode|aider'

opt() { # opt <@option> <default>
  local v
  v="$(tmux show-option -gqv "$1" 2>/dev/null)"
  printf '%s' "${v:-$2}"
}

# ---------------------------------------------------------------- detection

# Emit one line per agent pane:
#   pane_id \t rank \t status \t session \t win_idx \t win_name \t title \t path
scan() {
  local pattern
  pattern="$(opt @agent-jump-pattern "$DEFAULT_PATTERN")"

  tmux list-panes -a \
    -F '#{pane_id}	#{pane_pid}	#{session_name}	#{window_index}	#{window_name}	#{pane_title}	#{pane_current_path}' |
  awk -v pat="$pattern" '
    BEGIN {
      FS = OFS = "\t"
      # one ps call: build pid -> ppid and pid -> command maps
      cmd = "ps -axo pid=,ppid=,command="
      while ((cmd | getline line) > 0) {
        sub(/^[ \t]+/, "", line)
        split(line, f, /[ \t]+/)
        pid = f[1]; par = f[2]
        ppid[pid] = par
        kids[par] = kids[par] " " pid
        # keep only the first two tokens (executable + first arg) for matching,
        # so `nvim CLAUDE.md` does not false-positive but
        # `node /x/claude/cli.js` and `/x/claude/versions/2.1.198 --flag` do.
        head = f[3] (f[4] != "" ? " " f[4] : "")
        exe[pid] = head
      }
      close(cmd)
    }
    {
      # BFS the pane pid subtree looking for an agent process
      n = 1; queue[1] = $2; found = 0
      for (i = 1; i <= n && !found; i++) {
        p = queue[i]
        if (i > 1 && tolower(exe[p]) ~ tolower(pat)) { found = 1; break }
        m = split(kids[p], ch, " ")
        for (j = 1; j <= m; j++) if (ch[j] != "") queue[++n] = ch[j]
        if (n > 512) break
      }
      if (found) print $1, $3, $4, $5, $6, $7
      delete queue
    }
  ' |
  while IFS='	' read -r pane_id session win_idx win_name title path; do
    local status rank
    status="$(pane_status "$pane_id")"
    case "$status" in
      waiting) rank=0 ;;
      busy)    rank=1 ;;
      *)       rank=2 ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$pane_id" "$rank" "$status" "$session" "$win_idx" "$win_name" "$title" "$path"
  done | sort -t '	' -k2,2n -k4,4 -k5,5n
}

pane_status() { # <pane_id> -> waiting | busy | idle
  local tail_lines
  tail_lines="$(tmux capture-pane -p -t "$1" 2>/dev/null | tail -n 25)"
  if printf '%s' "$tail_lines" | grep -qE 'Do you want|Would you like|❯ 1\. Yes'; then
    printf 'waiting'
  elif printf '%s' "$tail_lines" | grep -qE 'esc to interrupt|^ ?(✻|✽|✶|✳|✢|✺|·) [A-Z][A-Za-z]+…'; then
    printf 'busy'
  else
    printf 'idle'
  fi
}

# ---------------------------------------------------------------- rendering

# Display width: non-ASCII counts as 2 columns, except common narrow
# punctuation/symbols (…·—–‘’“”) which render 1 column wide.
dwidth() {
  local wide="${1//[[:ascii:]]/}"
  wide="${wide//[…·—–‘’“”]/}"
  printf '%s' "$(( ${#1} + ${#wide} ))"
}

# Truncate to <width> display columns (… suffix) and pad with spaces.
fit() { # <str> <width>
  local s="$1" max="$2" w
  w="$(dwidth "$s")"
  if [ "$w" -gt "$max" ]; then
    while s="${s%?}"; [ "$(dwidth "$s")" -gt "$((max - 1))" ]; do :; done
    s="${s}…"
    w="$(dwidth "$s")"
  fi
  printf '%s%*s' "$s" "$((max - w))" ''
}

# Colored fzf lines: "pane_id \t <display>"
# AGENT_JUMP_CURRENT (optional) marks the pane the popup was opened from.
list() {
  scan | while IFS='	' read -r pane_id rank status session win_idx win_name title path; do
    local color label branch here
    case "$status" in
      waiting) color='\033[1;33m' label='▲ needs you' ;;
      busy)    color='\033[1;36m' label='✻ working  ' ;;
      *)       color='\033[2m'    label='○ idle     ' ;;
    esac

    # Claude Code sets pane_title to the conversation topic; the default shell
    # title looks like "user@host: path" — fall back to the window name then.
    case "$title" in
      *@*:*) title="$win_name" ;;
    esac

    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    here='  '; [ "$pane_id" = "${AGENT_JUMP_CURRENT:-}" ] && here='◂ '

    printf '%s\t%s%b%s\033[0m  \033[1m%s\033[0m  %s  \033[2m%s%s\033[0m\n' \
      "$pane_id" "$here" "$color" "$label" \
      "$(fit "$session:$win_idx" 14)" "$(fit "$title" 34)" \
      "${branch:+⎇ $branch · }" "${path/#"$HOME"/\~}"
  done
}

counts() { # -> "busy waiting idle"
  scan | awk -F '\t' '
    $3 == "busy"    { b++ }
    $3 == "waiting" { w++ }
    $3 == "idle"    { i++ }
    END { print b+0, w+0, i+0 }'
}

# status-right segment (tmux format markup)
status_line() {
  local b w i out=''
  read -r b w i <<EOF
$(counts)
EOF
  [ "$((b + w + i))" -eq 0 ] && return 0
  [ "$w" -gt 0 ] && out="$out#[fg=yellow,bold]▲$w#[default] "
  [ "$b" -gt 0 ] && out="$out#[fg=cyan]✻$b#[default] "
  [ "$i" -gt 0 ] && out="$out#[fg=colour244]○$i#[default] "
  printf '%s' "${out% }"
}

# ---------------------------------------------------------------- picker

picker() {
  local lines sel pane_id
  lines="$(list)"

  if [ -z "$lines" ]; then
    printf '\n   No agent panes found.\n\n   (pattern: %s)\n\n   press any key to close' \
      "$(opt @agent-jump-pattern "$DEFAULT_PATTERN")"
    read -rsn1
    return 0
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    printf '\n   tmux-agent-jump needs fzf:  brew install fzf\n\n   press any key to close'
    read -rsn1
    return 0
  fi

  sel="$(printf '%s\n' "$lines" | fzf \
    --ansi --reverse --no-info --cycle \
    --delimiter='\t' --with-nth=2.. \
    --prompt='  ' --pointer='▌' \
    --header='enter jump · ctrl-r refresh · esc close' \
    --header-first \
    --color='header:dim,pointer:cyan,hl:cyan,hl+:cyan,bg+:236,gutter:-1,border:240' \
    --preview="tmux capture-pane -ep -t {1}" \
    --preview-window='right,55%,border-left' \
    --bind="ctrl-r:reload('$SELF' list)")" || return 0

  pane_id="${sel%%	*}"
  [ -n "$pane_id" ] && jump "$pane_id"
}

jump() { # <pane_id>
  local target session win_idx
  target="$(tmux display-message -p -t "$1" '#{session_name}:#{window_index}' 2>/dev/null)" || return 0
  session="${target%%:*}"
  win_idx="${target##*:}"
  tmux select-pane -t "$1" 2>/dev/null
  tmux select-window -t "$session:$win_idx" 2>/dev/null
  tmux switch-client -t "$session" 2>/dev/null
}

popup() {
  local w h cur
  w="$(opt @agent-jump-width 90%)"
  h="$(opt @agent-jump-height 75%)"
  # run-shell context: resolves to the pane the keybinding was pressed in
  cur="$(tmux display-message -p '#{pane_id}' 2>/dev/null)"
  tmux display-popup -E -b rounded -S 'fg=colour240' -T ' ✻ agents ' \
    -w "$w" -h "$h" "AGENT_JUMP_CURRENT='$cur' '$SELF' picker"
}

# ---------------------------------------------------------------- main

case "${1:-popup}" in
  scan)   scan ;;
  list)   list ;;
  counts) counts ;;
  status) status_line ;;
  picker) picker ;;
  jump)   jump "${2:?pane_id required}" ;;
  popup)  popup ;;
  *)      echo "usage: agent-jump.sh [popup|picker|list|counts|status|jump <pane_id>]" >&2; exit 1 ;;
esac
