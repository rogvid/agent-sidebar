---
name: agent-sidebar
description: Operate the tmux agent-sidebar ecosystem - discover agents with agent-scan, find sessions working on specific projects/branches, and send messages between tmux panes. Use whenever you need to locate agents, check what they are doing, message another session, spawn worktrees/sessions from an orchestrator, or keep work visible in tmux worktrees. Triggers on agent-sidebar, agent-scan, tmux pane/session, worktree orchestration, or inter-agent messaging.
---

# Agent Sidebar

You have a sidebar, a scanner and plain tmux around them. The sidebar is for humans - you use `agent-scan` and `tmux` directly.

## The pieces

| Tool | What it is | You use it for |
|------|------------|----------------|
| `agent-scan` | Scans every tmux pane for an agent process | Discovery - who exists, what state they are in |
| `agent-sidebar` | Textual TUI shown left of the current window (M-2) | Not for you - the user sees it. You drive the same data via `agent-scan --json` |
| `agent-sidebar-tmux` | Keeps the sidebar pane following the viewed window + actions on panes | Spawn/review/git/pr actions - call via `agent-sidebar-tmux <cmd>` |
| `tmux send-keys / capture-pane / list-panes` | tmux itself | Messaging and inspection |

`git-wt` names worktrees/sessions: `<project>/main` is the main worktree, `feat-x` lives at `<project>/feat-x` with tmux session `<project>-feat-x`. Every worktree of a project shares its `.bare` dir.

## 1. Discover agents

Always prefer `--json` - stable fields, no truncation.

```bash
agent-scan --json | jq .
```

Each row:

```json
{
  "pane_id": "%42",
  "target": "dotfiles:1.0",
  "project": "dotfiles",
  "branch": "feat/foo",
  "cwd": "/home/kvist/projects/dotfiles/feat-foo",
  "agent": "claude",
  "state": "done",
  "context": "12.3k",
  "context_level": "ok",
  "duration": "2m",
  "since": 120.0,
  "message": "Fixed the sidebar toggle",
  "flag": " ",
  "block": "1h",
  "weekly": "-",
  "age": "3h"
}
```

Other outputs (human-oriented, avoid for automation):
- `agent-scan` (no flags) - pretty table
- `agent-scan --tmux` - `#[fg=...]● 2` for the tmux status bar, empty when no agents

Fields you filter on:
- `project` - repo name (worktrees of one project share this)
- `branch` - git branch or `@<sha>` / `no git`
- `state` - queue order: `blocked > interrupted > done > running > delegated`. `blocked/interrupted/done` need you; `running/delegated` do not.
- `cwd` - real working directory
- `pane_id` - stable tmux id (`%12`). Use this to address a pane, not `target` (window indices shift).
- `flag` - `"▲"` when two agents share one working tree (danger - they overwrite each other)
- `message` - last thing the pane said (spinner text while running, question while blocked, summary while done)

Rows arrive already sorted as a queue - most urgent first, freshest within each state.

### Useful filters

```bash
# All agents for a project
agent-scan --json | jq '[.[] | select(.project == "dotfiles")]'

# Who is blocked or done (needs attention)
agent-scan --json | jq '[.[] | select(.state == "blocked" or .state == "done")]'

# Find the pane working on a branch
agent-scan --json | jq -r '.[] | select(.branch == "feat/foo") | .pane_id'

# Find by message content
agent-scan --json | jq '[.[] | select(.message | contains("PR #"))]'

# Just pane ids + what they do (for picking a target)
agent-scan --json | jq -r '.[] | "\(.pane_id) \(.project)/\(.branch) \(.state): \(.message)"'
```

If `agent-scan --json` returns `[]`, there are no agent panes.

## 2. Find sessions working on specific things

Combine `agent-scan --json` with `jq` and tmux:

```bash
# Is there an agent on feat/foo? What state?
agent-scan --json | jq -r '.[] | select(.branch == "feat/foo") | "\(.pane_id) \(.state) \(.message)"'

# Working directories for all dotfiles worktrees
agent-scan --json | jq -r '.[] | select(.project == "dotfiles") | .cwd' | sort -u

# Outside agent-scan: list all worktrees and their sessions (even idle ones)
git -C ~/projects/dotfiles worktree list --porcelain
git-wt list          # merge + work state per worktree
git-wt session ~/projects/dotfiles/feat-foo   # -> "dotfiles-feat-foo<TAB>/path"
tmux list-sessions -F '#{session_name} #{session_windows}w #{session_attached}'
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path} #{pane_current_command}'
```

Prefer `agent-scan` when you care about *agent* state; use `git-wt`/`tmux list-*` when you care about *worktree/session existence* even without an agent.

## 3. Send messages to another session

You are in a tmux pane. The target is another pane's `pane_id`.

### Basic send

```bash
# Type into the pane and press Enter (like a human)
tmux send-keys -t "%42" "hello, continue with the fix" Enter

# Multiline via heredoc-style paste (bracketed paste, no Enter until you send it)
tmux load-buffer -b agent-msg "Fix the failing test in scripts/tests/test-agent-scan

Details:
- file: scripts/tests/test-agent-scan line 120
- expected: blocked state"

tmux paste-buffer -p -d -b agent-msg -t "%42"
# Optionally press Enter after pasting if you want it submitted:
tmux send-keys -t "%42" Enter
```

### Rules for messaging

- **Use `pane_id` (`%12`)**, never `session:window.pane` - indices move.
- **Bracketed paste** (`load-buffer` + `paste-buffer -p`) is safer than `send-keys` for anything with newlines, quotes, or `#`/`{}` (tmux formats expand `#`).
- **`-p` means bracketed** - the target app receives it as a paste, not keystrokes.
- **`-d` deletes the buffer** after pasting.
- Check before you spam: `tmux capture-pane -p -t "%42" | tail -n 30` shows if the agent is `blocked` waiting for input vs `running` mid-turn. Interrupting a `running` pane is expensive.
- If you need to interrupt, `tmux send-keys -t "%42" C-c` (or `Escape`) first, then paste.
- After messaging, verify: `agent-scan --json | jq '.[] | select(.pane_id=="%42")'` should show state change within 1-2s. Poll once.

### Read first, then write

```bash
# What is pane %42 actually showing right now?
tmux capture-pane -p -t "%42" | tail -n 40

# What does agent-scan think?
agent-scan --json | jq '.[] | select(.pane_id=="%42")'

# Only then decide to send.
```

## 4. Orchestrator pattern - one main session spawning workers

This is the main reason the sidebar exists: a single control session visible alongside worker worktrees.

```bash
# From the main session, create a worktree + session and start an agent in it.
# Uses the same path/session naming as everywhere else, so it lands in the sidebar.

# Option A: via agent-sidebar-tmux (preferred - handles naming + tmux)
agent-sidebar-tmux new-worktree "%current_pane_id" "feat/my-feature"

# Option B: direct git-wt + tmux (when you need control)
git-wt add "feat/my-feature"          # creates ~/projects/<project>/feat-my-feature
path=$(git -C ~/projects/<project> worktree list --porcelain | awk '/^worktree /{p=$2} /^branch refs\/heads\/feat\/my-feature/{print p}')
session=$(git-wt session "$path" | cut -f1)
tmux new-session -d -s "$session" -c "$path"
tmux send-keys -t "=$session:" "claude" Enter
tmux switch-client -t "=$session"     # optional: jump there
```

Tracking workers from the orchestrator:

```bash
# Poll loop - who needs me?
while true; do
  agent-scan --json | jq -r '.[] | "\(.state) \(.project)/\(.branch) \(.pane_id): \(.message)"'
  sleep 2
done

# Act on the queue top (blocked first)
next=$(agent-scan --json | jq -r '.[0].pane_id // empty')
[ -n "$next" ] && tmux capture-pane -p -t "$next" | tail -n 20
```

When a worker finishes (`state == "done"`), send it the next instruction or review its changes:

```bash
# Review uncommitted changes of a worker (same as sidebar's `d`)
agent-sidebar-tmux review "%42"

# Or plain git
git -C "$(tmux display-message -p -t "%42" '#{pane_current_path}')" diff
git -C "$(tmux display-message -p -t "%42" '#{pane_current_path}')" log --oneline -5
```

Cleaning up:

```bash
# Remove a worker's worktree when merged/done (asks, refuses if dirty)
agent-sidebar-tmux remove-worktree "%42"
# Direct:
git-wt remove --discard ~/projects/<project>/feat-my-feature  # only with --discard if dirty
tmux kill-pane -t "%42"  # or kill-session if it was the last pane
```

## 5. Sidebar actions you can call headless

These all take a `pane_id` and were built for the sidebar but work from any pane. They run in a tmux popup when a human triggers them; headless they still work.

```bash
agent-sidebar-tmux new-worktree <pane_id> <branch>   # branch must be new
agent-sidebar-tmux review <pane_id>                  # tuicr review, y pastes comments
agent-sidebar-tmux git <pane_id>                     # lazygit in pane's cwd
agent-sidebar-tmux pr <pane_id>                      # gh pr view / create
agent-sidebar-tmux kill <pane_id>                    # kill-pane
agent-sidebar-tmux remove-worktree <pane_id>         # git-wt-remove + kill
agent-sidebar-tmux open                              # tv projects picker

# Sidebar pane itself
agent-sidebar-tmux toggle    # M-2
agent-sidebar-tmux close
agent-sidebar-tmux follow    # hook - moves sidebar to viewed window
```

Env overrides: `AGENT_SIDEBAR_WIDTH` (default 36), `AGENT_SIDEBAR_COMMAND` (default `agent-sidebar`), `AGENT_SIDEBAR_AGENT` (default `claude`).

## 6. tmux gotchas

- `TMUX` and `TMUX_PANE` are set inside tmux. Outside (e.g. a test harness) they are empty; `agent-scan` then finds zero panes and `send-keys` fails. Always run inside tmux or set `TMUX` to the socket from `tmux display-message -p '#{socket_path},#{pid},0'`.
- `pane_id` is `%` + number. Quote it: `tmux send-keys -t "%42"` not `-t %42` alone if your shell does job control.
- `tmux display-message -p -t "%42" '#{pane_current_path}'` gives the cwd of that pane.
- Hooks fire in bursts - `agent-sidebar-tmux follow` is already idempotent and lock-guarded. Do not call it in a tight loop.
- No nested clients: a popup that does `tmux attach` is a second client; `viewed_window` logic ignores server-spawned clients.

## 7. Anti-patterns

- Do not parse `agent-scan` human table - use `--json`.
- Do not use `target` (`session:window.pane`) to address panes in scripts - it renumbers.
- Do not `send-keys` a large prompt without bracketed paste - `#` and `#{}` will be expanded as tmux formats.
- Do not poll `agent-scan` faster than 1s - it walks the process tree and captures panes.
- Do not assume a pane is idle because `message` is short - check `state`. `running` means do not interrupt unless you must.
