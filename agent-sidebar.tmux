#!/usr/bin/env bash
# agent-sidebar as a tmux plugin: TPM runs this when tmux loads its config,
# and so does `run-shell /path/to/agent-sidebar.tmux` without TPM.
#
# Options, set before TPM runs (`set -g @agent-sidebar-key M-s`):
#
#   @agent-sidebar-key      the key that shows or closes the sidebar, with no
#                           prefix (default M-2); "off" binds none
#   @agent-sidebar-status   "off" leaves status-right alone; otherwise the
#                           agent counts go in front of it (default on)
#
# Safe to run again: a re-source replaces what the last run set up rather
# than stacking another copy.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin="${dir}/bin"

option() {
    local value
    value="$(tmux show-options -gqv "$1")"
    printf '%s\n' "${value:-$2}"
}

# The tools run one another by name, and so do agents in tmux panes (the
# skill tells them to run agent-scan and agent-msg), so bin goes on PATH for
# every new pane and every job the server runs.
path="$(tmux show-environment -g PATH 2>/dev/null)" || path="PATH=${PATH}"
path="${path#PATH=}"
case ":${path}:" in
    *":${bin}:"*) ;;
    *) tmux set-environment -g PATH "${bin}:${path}" ;;
esac

key="$(option @agent-sidebar-key M-2)"
if [[ "${key}" != off ]]; then
    tmux bind-key -n "${key}" run-shell "'${bin}/agent-sidebar-tmux' toggle"
fi

# The sidebar is one pane that these move into whichever window you are
# looking at. The [10] slot keeps a re-source from stacking copies and
# leaves the unindexed slot to other plugins.
for hook in session-window-changed client-session-changed client-attached \
        client-resized window-layout-changed after-resize-pane pane-exited \
        after-kill-pane; do
    tmux set-hook -g "${hook}[10]" \
        "run-shell -b \"'${bin}/agent-sidebar-tmux' follow\""
done

if [[ "$(option @agent-sidebar-status on)" != off ]]; then
    status="$(tmux show-options -gv status-right)"
    if [[ "${status}" != *agent-scan*--tmux* ]]; then
        tmux set-option -g status-right "#('${bin}/agent-scan' --tmux)${status}"
    fi
fi

# agent-msg queues a message its recipient cannot take yet, such as one
# blocked on a dialog; this pastes it once it can, and tells its sender if
# it waits long, for as long as the server runs. Only one runs, so a
# re-source starts no second. Its output goes nowhere: tmux would keep a
# job's output for as long as it runs, which is as long as the server.
tmux run-shell -b "'${bin}/agent-msg' deliver --watch >/dev/null 2>&1"

# tmux-resurrect would bring a saved sidebar back as a bare shell in its
# slot. Only when nothing else has claimed the hook.
if [[ -z "$(tmux show-options -gqv @resurrect-hook-post-save-layout)" ]]; then
    tmux set-option -g @resurrect-hook-post-save-layout \
        "'${bin}/agent-sidebar-tmux' prune-resurrect"
fi
