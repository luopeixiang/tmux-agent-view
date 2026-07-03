#!/usr/bin/env bash
# tmux-agent-view — TPM entry point

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$CURRENT_DIR/scripts/agent-view.sh"

get_opt() {
  local v
  v="$(tmux show-option -gqv "$1")"
  printf '%s' "${v:-$2}"
}

key="$(get_opt @agent-view-key 'a')"
tmux bind-key "$key" run-shell "$SCRIPT popup"

# Append the agent summary to status-right once (idempotent).
if [ "$(get_opt @agent-view-status 'on')" = "on" ]; then
  status_right="$(tmux show-option -gv status-right)"
  case "$status_right" in
    *agent-view.sh*) ;;
    *) tmux set-option -g status-right "#($SCRIPT status) $status_right" ;;
  esac
fi
