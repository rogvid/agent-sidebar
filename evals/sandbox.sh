#!/usr/bin/env bash
# A throwaway world for the agent-sidebar evals, driven by ./run: a tmux
# server of its own with a client attached, two git-wt projects (shop, with an
# agent on feat/login, and blog) and stub agents that record what reaches
# them. Nothing here touches your tmux server.
#
#   sandbox.sh up DIR                  build it
#   sandbox.sh ask DIR MODEL PROMPT    run the agent under test in the user's pane
#   sandbox.sh again DIR MODEL PROMPT  a second turn in the same opencode session
#   sandbox.sh down DIR                stop its tmux servers
#
# The agent under test is opencode on a free model, through opencode-free:
# OPENCODE_FREE_TMUX_TMPDIR hands it this sandbox's server and no other.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
readonly here
readonly cmd="$1" dir="$2"
shift 2
# The default socket of $dir/tmux, which is where opencode-free points the
# agent's tmux.
socket="${dir}/tmux/tmux-$(id -u)/default"
host="agent-sidebar-eval-$(basename "${dir}")"
readonly socket host

t() { tmux -S "${socket}" "$@"; }

up() {
    rm -rf "${dir}"
    mkdir -p "${dir}"/{stubs,logs,src,projects} "$(dirname "${socket}")"
    chmod 700 "$(dirname "${socket}")"

    # A stand-in harness: a bash script named claude (a direct #!/bin/bash, so
    # the process keeps that name and agent-scan lists it). Like the real one
    # it ignores what is typed while it boots; then it turns on bracketed
    # paste and logs its arguments and every byte it receives.
    cat >"${dir}/stubs/claude" <<EOF
#!/bin/bash
log="${dir}/logs/\${TMUX_PANE#%}"
printf '%s\n' "\$*" >"\${log}.args"
sleep 3
python3 -c 'import termios; termios.tcflush(0, termios.TCIFLUSH)'
printf '\e[?2004h'
printf '╭─ claude (stub) ─╮\n\n❯ '
stty raw -echo
cat >"\${log}.in"
EOF
    chmod +x "${dir}/stubs/claude"

    local project
    for project in shop blog; do
        git -c init.defaultBranch=main init -q "${dir}/src/${project}"
        printf '# %s\n\nTeh %s app.\n\nRun: python app.py, then open http://localhost:8000\n' \
            "${project}" "${project}" >"${dir}/src/${project}/README.md"
        cp -r "${here}/app/." "${dir}/src/${project}/"
        git -C "${dir}/src/${project}" add -A
        git -C "${dir}/src/${project}" -c user.name=eval -c user.email=eval@example.com \
            commit -qm init
        (cd "${dir}/projects" && git-wt clone "${dir}/src/${project}" "${project}" >/dev/null 2>&1)
    done
    (cd "${dir}/projects/shop/main" && git-wt add feat/login >/dev/null 2>&1)

    # Shells that keep the stubs first on PATH: zsh's rc files would put the
    # real claude back in front. PATH entries with spaces (Windows ones under
    # WSL) would split the command, so they are left out. The agent-sidebar
    # state, agent-msg's log among it, stays in the sandbox.
    local path
    path="${dir}/stubs:$(tr : '\n' <<<"${PATH}" | grep -v ' ' | paste -sd:)"
    printf 'set -g default-command "env PATH=%s XDG_STATE_HOME=%s bash --norc --noprofile"\n' \
        "${path}" "${dir}/state" >"${dir}/tmux.conf"
    t -f "${dir}/tmux.conf" new-session -d -s shop -c "${dir}/projects/shop/main" -x 200 -y 50
    t new-session -d -s shop-feat-login -c "${dir}/projects/shop/feat-login" -x 200 -y 50
    t send-keys -t =shop-feat-login: claude Enter
    t new-session -d -s blog -c "${dir}/projects/blog/main" -x 200 -y 50
    t send-keys -t =blog: claude Enter
    # The user's screen: a client attached to shop, so popups have somewhere
    # to go and a switch-client would show.
    tmux -L "${host}" -f /dev/null new-session -d -s host -x 220 -y 60 \
        "env -u TMUX tmux -S ${socket} attach -t shop"
    sleep 4
}

# Type the agent's command into the user's pane (shop, %0) and wait for it.
turn() {
    local model="$1" prompt="$2" session="${3:-}" resume=""
    printf '%s' "${prompt}" >"${dir}/prompt"
    [[ -n "${session}" ]] && resume="--session ${session} "
    t send-keys -t =shop: -l "cd ${dir}/projects/shop/main && OPENCODE_FREE_MODELS=${model} OPENCODE_FREE_TMUX_TMPDIR=${dir}/tmux opencode-free ${resume}--format json \"\$(cat ${dir}/prompt)\" </dev/null >>${dir}/out.jsonl 2>>${dir}/err.log; tmux wait-for -S turn-done"
    t send-keys -t =shop: Enter
    timeout 900 tmux -S "${socket}" wait-for turn-done
}

ask() { turn "$1" "$2"; }

again() {
    local session
    session="$(grep -o '"sessionID":"[^"]*"' "${dir}/out.jsonl" | head -1 | cut -d'"' -f4)"
    turn "$1" "$2" "${session}"
}

down() {
    local host_socket
    host_socket="$(tmux -L "${host}" display-message -p '#{socket_path}' 2>/dev/null || true)"
    tmux -L "${host}" kill-server 2>/dev/null || true
    t kill-server 2>/dev/null || true
    # kill-server leaves the socket file behind in tmux's shared directory.
    [[ -n "${host_socket}" ]] && rm -f "${host_socket}"
    return 0
}

"${cmd}" "$@"
