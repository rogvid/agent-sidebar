#!/usr/bin/env bash
# The world demo.tape records: a throwaway HOME with two git-wt projects,
# four stand-in agents in them (demo/bin/claude), a tmux server of its own
# running the plugin, and an account's usage for the sidebar's meters.
#
#   demo/sandbox.sh          build it and start the server
#   demo/sandbox.sh clean    stop the server and remove it all
#
# Then: tmux -L agent-sidebar-demo attach -t shop
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
readonly repo
# Short: tmux sockets live under it, and a socket path has a length limit.
readonly root="/tmp/agent-sidebar-demo"
readonly socket="agent-sidebar-demo"

t() { tmux -L "${socket}" "$@"; }

if [[ "${1:-}" == clean ]]; then
    t kill-server 2>/dev/null || true
    rm -rf "${root}"
    exit 0
fi

t kill-server 2>/dev/null || true
rm -rf "${root}"
# The uv scripts would otherwise fetch a Python into the throwaway HOME.
UV_CACHE_DIR="$(uv cache dir)" UV_PYTHON_INSTALL_DIR="$(uv python dir)"
export UV_CACHE_DIR UV_PYTHON_INSTALL_DIR
export HOME="${root}/home"
export XDG_CONFIG_HOME="${HOME}/.config" XDG_STATE_HOME="${HOME}/.local/state"
export PATH="${repo}/demo/bin:${repo}/bin:${PATH}"
unset TMUX TMUX_PANE CLAUDE_CONFIG_DIR CODEX_HOME PI_CODING_AGENT_DIR
mkdir -p "${HOME}/projects"

git() {
    command git -c user.name=demo -c user.email=demo@example.com \
        -c commit.gpgsign=false -c init.defaultBranch=main "$@"
}

# project NAME BRANCH...: git-wt's layout, with a worktree per branch.
project() {
    local dir="${HOME}/projects/$1" branch
    shift
    git init -q --bare "${dir}/.bare"
    echo 'gitdir: ./.bare' >"${dir}/.git"
    git -C "${dir}" worktree add -q --orphan -b main "${dir}/main"
    git -C "${dir}/main" commit -q --allow-empty -m init
    for branch in "$@"; do
        git -C "${dir}/main" worktree add -q -b "${branch}" \
            "${dir}/$(printf '%s' "${branch}" | tr '/' '-')"
    done
}
project shop feat/checkout fix/cart-rounding
project api feat/rate-limit

# An account with a plan, and usage the sidebar shows at its bottom.
mkdir -p "${HOME}/.claude"
echo '{"oauthAccount": {"organizationType": "claude_max"}}' >"${HOME}/.claude.json"
usage="${XDG_STATE_HOME}/agent-sidebar/usage"
mkdir -p "${usage}"
folder="$(realpath "${HOME}/.claude")"
now="$(date +%s)"
jq -nc --arg folder "${folder}" --argjson five "$((now + 2 * 3600 + 900))" \
    --argjson week "$((now + 3 * 86400))" \
    '{harness: "claude", folder: $folder,
      five_hour: {used_percentage: 38, resets_at: $five},
      seven_day: {used_percentage: 64, resets_at: $week}}' \
    >"${usage}/claude-$(printf '%s' "${folder}" | md5sum | cut -c1-16).json"

cat >"${root}/tmux.conf" <<EOF
set -g default-shell /bin/bash
set -g default-command "env PATH='${PATH}' bash --norc --noprofile"
# vhs cannot type Alt+2, but Escape then 2 inside this window is read as M-2.
set -g escape-time 300
set -g automatic-rename off
set -g status-style "bg=#313244,fg=#cdd6f4"
set -g status-left "#[bold] #S "
set -g status-left-length 30
set -g status-right " %H:%M "
# The counts keep up with the sidebar, as they would over a longer look.
set -g status-interval 1
# The session name says where you are; window names would only repeat it.
set -g window-status-format ""
set -g window-status-current-format ""
set -g pane-border-style "fg=#45475a"
set -g pane-active-border-style "fg=#45475a"
run-shell '${repo}/agent-sidebar.tmux'
EOF

# agent SESSION FOLDER SCENE [VAR=VALUE...]: a session running a stand-in
# claude in FOLDER.
agent() {
    local session="$1" dir="$2" scene="$3"
    shift 3
    t new-session -d -s "${session}" -n claude -x 200 -y 50 -c "${dir}" \
        env AGENT_DEMO_SCENE="${scene}" "$@" claude
}

shop="${HOME}/projects/shop" api="${HOME}/projects/api"
t -f "${root}/tmux.conf" start-server \; set -g exit-empty off
t source-file "${root}/tmux.conf"
agent shop "${shop}/main" "done" \
    "AGENT_DEMO_TASK=why do some carts show a total of 0.30000000000000004?" \
    "AGENT_DEMO_REPLY=Totals are summed in cents now. fix/cart-rounding has the fix and a test."
agent shop-feat-checkout "${shop}/feat-checkout" running \
    "AGENT_DEMO_TASK=add a checkout form with address validation" \
    "AGENT_DEMO_STEP=Writing the address validation tests" \
    "AGENT_DEMO_REPLY=The checkout form validates addresses as you type. All 42 tests pass." \
    AGENT_DEMO_SECONDS=14
agent shop-fix-cart-rounding "${shop}/fix-cart-rounding" running \
    "AGENT_DEMO_TASK=sum cart totals in cents" \
    "AGENT_DEMO_STEP=Running the cart test suite" AGENT_DEMO_SECONDS=600
agent api-feat-rate-limit "${api}/feat-rate-limit" blocked \
    "AGENT_DEMO_TASK=rate limit the public API" \
    "AGENT_DEMO_NEXT_STEP=Applying the edit to limits.ts" \
    "AGENT_DEMO_NEXT_REPLY=Every public route is limited to 100 requests a minute per key."
