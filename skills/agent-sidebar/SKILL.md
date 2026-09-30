---
name: agent-sidebar
description: Operate the tmux agent-sidebar ecosystem - discover agents with agent-scan, find sessions working on specific projects/branches, and send messages between tmux panes. Use whenever you need to locate agents, check what they are doing, message another session, spawn worktrees/sessions with a harness from an orchestrator, or keep work visible in tmux worktrees. Triggers on agent-sidebar, agent-scan, tmux pane/session, worktree orchestration, or inter-agent messaging.
---

# Agent Sidebar

You have a sidebar, a scanner and plain tmux around them.
The sidebar is for humans - you use `agent-scan`, `git-wt` and `tmux` directly.

## The pieces

| Tool | What it is | You use it for |
|------|------------|----------------|
| `agent-scan` | Scans every tmux pane for a harness process | Discovery - who exists, what state they are in |
| `agent-sidebar` | Textual TUI down the left of the viewed window (M-2) | Not for you - the user sees it. You get the same data from `agent-scan --json` |
| `agent-usage-tap` | Sits in front of Claude's statusline command and keeps each account's rate limits | Reading how much of an account's 5h and weekly limits is used (section 5) |
| `agent-sidebar-tmux` | Moves the sidebar pane with the viewed window, and runs the sidebar's actions on panes | Spawning worktrees, killing panes; the rest are interactive popups for the human |
| `agent-sidebar-config` | Reads the settings file for the other tools | Checking the settings (section 5) |
| `git-wt` | Worktree and session naming | Creating/removing worktrees, finding a worktree's session |
| `tmux send-keys / paste-buffer / capture-pane / list-panes` | tmux itself | Messaging and inspection |

`git-wt` layout: a project folder holds `.bare` (shared by every worktree) and one folder per branch, folded to lowercase letters, digits and dashes.
Branch `feat/x` lives at `<project-dir>/feat-x` with tmux session `<project>-feat-x`.
The main branch's worktree is `<project-dir>/main` (or whatever the main branch is called) with session `<project>`.
Projects are not all under one root, so never hardcode a path like `~/projects/<project>` - take it from `cwd` or `git-wt session`.

## 1. Discover agents

Always use `--json` - stable fields, project and branch never cut short.

```bash
agent-scan --json | jq .
```

Only harness processes make a pane an agent: `claude`, `codex`, `opencode`, `pi`.
A pane with none of them in its process tree is not listed.

Each row (real output):

```json
{
  "state": "done",
  "project": "dotfiles",
  "branch": "fix/sidebar-worktree-dialog",
  "target": "dotfiles-fix-sidebar-worktree-dialog:1.0",
  "pane_id": "%119",
  "cwd": "/home/kvist/personal/projects/dotfiles/fix-sidebar-worktree-dialog",
  "agent": "claude",
  "context": "91.6k",
  "duration": "2m",
  "since": 174.55,
  "block": "18m",
  "weekly": "-",
  "age": "9m",
  "message": "WORKER READY",
  "flag": " ",
  "harness": "claude",
  "role": "",
  "changes": "∅",
  "context_level": "ok",
  "account": "",
  "hidden": false
}
```

Other outputs (human-oriented, do not parse):
- `agent-scan` (or `--no-color`) - aligned table; a `hidden` column before the message when any agent is hidden
- `agent-scan --tmux` - `#[fg=green]● 14 #[fg=blue]● 1#[default] ` for the tmux status bar, empty when no agents; hidden agents are not counted

Fields:
- `pane_id` - stable tmux id (`%12`). Address panes with this, never `target` (window indices shift).
- `target` - `session:window.pane`, for reading only.
- `project` - repo name; every worktree of a project shares it.
- `branch` - checked-out branch, `@<sha>` when detached, `no git` outside a repository.
- `cwd` - the pane's working directory.
- `state` - `blocked > interrupted > done > running > delegated`. `blocked`/`interrupted`/`done` need you; `running`/`delegated` do not.
- `agent` and `harness` - both the harness name: `claude`, `codex`, `opencode` or `pi`.
- `role` - only the harness's `--agent NAME` (lowercased), `""` when started without one. `opencode` without `--agent` reports `build`.
- `changes` - `+A -D` lines from the pane's statusline `(+A,-D)`, else from `git diff` (staged + unstaged); `+N untracked` when only untracked files; `∅` when clean; `-` when unknown (not a git repo).
- `context` - context size from the statusline (`91.6k`, `1.2M`), `-` when unknown. `context_level` is `ok`, `warn` (>= 100k), `rot` (>= 400k) or `unknown`.
- `duration` - how long in the current state, `-` when the screen does not show it. `since` is the same in seconds, or `null`.
- `block` - the 5h usage block from the statusline (account-wide), `-` when not shown.
- `weekly` - `NN%` of the weekly limit when the harness shows that notice, else `-`.
- `age` - session age from the statusline, else since the harness process started.
- `message` - first line of the last thing the pane said, max 160 chars (spinner text while running, the question while blocked, the summary while done).
- `message_full` - all of the last thing the pane said, uncut, as one line: a whole `※ recap:` or answer block. Read this instead of `tmux capture-pane` when you need what an agent reported.
- Both read `(scrolled up, last words off screen)` when a claude pane is scrolled up: its latest words are below the fold, and `duration` is `-` for the same reason.
- `flag` - `"▲"` when two agents share one working directory (danger - they overwrite each other), else `" "`.
- `account` - the folder of the account the harness runs on (`CLAUDE_CONFIG_DIR`, `CODEX_HOME` or `PI_CODING_AGENT_DIR` of its process), `""` on its default one. Match it against `agent-sidebar-tmux accounts` for the name.
- `hidden` - `true` when the pane's tmux session is in the config's `hide` list (see Configuration). The user does not see it in the sidebar or the status bar, but you can still find and message it.

Rows arrive sorted as a queue - most urgent state first, freshest within each state.
`agent-scan --json` prints `[]` when there are no agent panes.

### Useful filters

```bash
# All agents for a project
agent-scan --json | jq '[.[] | select(.project == "dotfiles")]'

# Who needs attention
agent-scan --json | jq '[.[] | select(.state == "blocked" or .state == "interrupted" or .state == "done")]'

# The pane working on a branch
agent-scan --json | jq -r '.[] | select(.branch == "feat/foo") | .pane_id'

# By message content
agent-scan --json | jq '[.[] | select(.message | contains("PR #"))]'

# By harness or role
agent-scan --json | jq -r '.[] | select(.harness == "opencode" and .role == "build") | .pane_id'

# Panes with uncommitted work
agent-scan --json | jq -r '.[] | select(.changes != "∅" and .changes != "-") | "\(.pane_id) \(.changes)"'

# One line per agent, for picking a target
agent-scan --json | jq -r '.[] | "\(.pane_id) \(.project)/\(.branch) \(.state): \(.message)"'
```

## 2. Find sessions working on specific things

```bash
# Is there an agent on feat/foo? What state?
agent-scan --json | jq -r '.[] | select(.branch == "feat/foo") | "\(.pane_id) \(.state) \(.message)"'

# Working directories of a project's agents
agent-scan --json | jq -r '.[] | select(.project == "dotfiles") | .cwd' | sort -u

# Worktrees and sessions, even without an agent (run inside the project)
git worktree list --porcelain
git-wt list --no-fetch                  # merge + work state per worktree; -a for every project
git-wt session "<worktree-dir>"         # -> "dotfiles-feat-foo<TAB>/abs/path"; for the project dir, the main worktree's
tmux list-sessions -F '#{session_name} #{session_windows}w #{session_attached}'
tmux list-panes -a -F '#{pane_id} #{session_name}:#{window_index}.#{pane_index} #{pane_current_path} #{pane_current_command}'
```

Use `agent-scan` for *agent* state, `git-wt`/`tmux list-*` for *worktree/session existence*.

## 3. Send messages to another pane

The target is another pane's `pane_id`.

```bash
# Short single-line message, submitted
tmux send-keys -t "%42" -l "hello, continue with the fix"
tmux send-keys -t "%42" Enter

# Multiline: bracketed paste from stdin, not submitted until you send Enter
tmux load-buffer -b agent-msg - <<'EOF'
Fix the failing test in scripts/tests/test-agent-scan

Details:
- expected: blocked state
EOF
tmux paste-buffer -p -d -b agent-msg -t "%42"
tmux send-keys -t "%42" Enter
```

Rules:
- **Use `pane_id` (`%12`)**, never `session:window.pane` - indices move.
- **Use `send-keys -l` for text.** Without `-l`, an argument that is a key name (`Enter`, `C-c`, `Escape`) is sent as that key.
- **A trailing `;` is a tmux command separator**, even with `-l`: `send-keys -l "done;"` sends `done`, and without `-l` the call fails. Write `\;` or use a paste.
- **Newlines need a paste.** `send-keys` turns each newline into Enter and submits early. `load-buffer -b NAME -` reads the text from stdin (`load-buffer` takes a file, not text); `set-buffer -b NAME "text"` also works.
- `paste-buffer -p` pastes bracketed, so the target treats it as a paste, not keystrokes; `-d` deletes the buffer afterwards.
- Read before you write: `tmux capture-pane -p -t "%42" | tail -n 40` and `agent-scan --json | jq '.[] | select(.pane_id=="%42")'`. Interrupting a `running` pane is expensive.
- To interrupt: `tmux send-keys -t "%42" Escape` (or `C-c`) first, then paste.
- After sending, poll `agent-scan` once after 1-2s to confirm the state changed.
- **A harness you just started is not listening yet.** For its first seconds, keys sent to it are lost - text can land in its input with the Enter dropped. Give a new agent its task on its launch command line (section 4), not as a message after it.
- Type a harness command into a pane only when its shell is in front: `tmux display-message -p -t "%42" '#{pane_current_command}'`. Typed into a running harness, it is just a message to that agent.

## 4. Orchestrator pattern - one main session spawning workers

A worker gets its task the moment it starts: as the launch command's prompt argument, never as a message sent after launch (see section 3).

| Harness | Start with a task | Yolo flag |
|---------|-------------------|-----------|
| `claude` | `claude "TASK"` | `--dangerously-skip-permissions` |
| `codex` | `codex "TASK"` | `--yolo` |
| `opencode` | `opencode --prompt "TASK"` | `--auto` |
| `pi` | `pi "TASK"` | none |

Write the task to a file first and let the new shell read it, so no quoting or length limit gets in the way:

```bash
brief=$(mktemp)
cat >"$brief" <<'EOF'
Fix the typo in README.md, then commit it.
EOF
launch="claude --dangerously-skip-permissions \"\$(cat $brief)\""   # typed as-is into the new shell
```

### Start it: `agent-sidebar-tmux spawn`

```bash
worker=$(agent-sidebar-tmux spawn "$TMUX_PANE" "feat/my-feature" "$launch")
```

`spawn PANE|DIR BRANCH [HARNESS] [--account NAME]`:
- Creates the worktree for BRANCH in PANE's project (or DIR's) with `git-wt-add` (an existing branch or worktree is reused); its report goes to stderr.
- Creates the worktree's own session, types HARNESS into its shell and prints that pane's id. The session outlives the harness.
- HARNESS is any command, the task included (`$launch` above); `none` starts nothing; default `$AGENT_SIDEBAR_AGENT` or `claude`.
- Nothing appears on the user's screen and they stay where they are.
- The worker runs on your account: the session keeps your `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `PI_CODING_AGENT_DIR`.
  Never set these in `$launch` yourself.
- `--account NAME` starts the harness on another of its accounts instead, only when the user asks for one; `agent-sidebar-tmux accounts` lists them.
- Fails with a message and a non-zero exit when PANE is not in a `git-wt` project, when the account is unknown, or when the worktree's session already exists - it never types into a session it did not create.

When it fails, stop and tell the user what it said.
Do not rebuild its steps by hand, and do not delete a session or worktree to make room.

After it succeeds, check once with `agent-scan` that the worker is listed. Do not type the launch command again - see section 3.
To bring the user to the worker only when they ask: `tmux switch-client -t "$worker"`.

`agent-sidebar-tmux new-worktree PANE BRANCH [HARNESS] [--account NAME]` is the sidebar's version for the human: `git-wt-add` runs in a popup on their screen, an existing session is reused as it is, and it switches their client to the new session.

### Tracking and reviewing workers

```bash
# Who needs me?
agent-scan --json | jq -r '.[] | "\(.state) \(.project)/\(.branch) \(.pane_id): \(.message)"'

# Queue top (most urgent first)
next=$(agent-scan --json | jq -r '.[0].pane_id // empty')
[ -n "$next" ] && tmux capture-pane -p -t "$next" | tail -n 20

# A worker's changes
dir=$(tmux display-message -p -t "%42" '#{pane_current_path}')
git -C "$dir" status --short
git -C "$dir" diff
git -C "$dir" log --oneline -5
```

### Cleaning up

```bash
# Run inside the project. TARGET is a branch, folder name or path.
# Asks y/N on stdin (-f skips that), refuses uncommitted/untracked work unless --discard,
# -d also deletes the branch if merged, and it closes the worktree's own session.
git-wt remove -f -d "feat/my-feature"
tmux kill-pane -t "%42"   # only if the worker's pane lived in another session
```

## 5. Sidebar actions

`agent-sidebar-tmux` actions take a `pane_id`.
All but `kill` and `spawn` open a `display-popup` on the attached client - they are for the human and fail with `no current client` when none is attached.

```bash
agent-sidebar-tmux new-worktree <pane_id> <branch> [harness] [--account name]  # see section 4
agent-sidebar-tmux spawn <pane_id|dir> <branch> [harness] [--account name]     # section 4; no popup, prints the new pane id
agent-sidebar-tmux accounts                   # each harness's accounts besides its default: harness, name, folder
agent-sidebar-tmux review <pane_id>           # tuicr on its uncommitted changes; export (y) is pasted into the pane unsubmitted
agent-sidebar-tmux git <pane_id>              # lazygit in the pane's cwd
agent-sidebar-tmux pr <pane_id>               # gh pr view, or offer gh pr create
agent-sidebar-tmux kill <pane_id>             # kill-pane, no popup
agent-sidebar-tmux remove-worktree <pane_id>  # git-wt-remove -d (asks), then kills the pane if the worktree is gone
agent-sidebar-tmux open                       # tv projects picker

# The sidebar pane itself
agent-sidebar-tmux toggle    # M-2
agent-sidebar-tmux close
agent-sidebar-tmux follow    # tmux hooks run this
```

The bottom of the sidebar shows, for each Claude account a running agent is on, how much of its 5h and weekly limits is used and when each resets.
You read the same from the files `agent-usage-tap` keeps, one per account; `resets_at` is Unix seconds, and a window past it has started over at an unknown number:

```bash
jq -c . "${XDG_STATE_HOME:-$HOME/.local/state}"/agent-sidebar/usage/claude-*.json
# {"harness":"claude","folder":"/home/u/.claude-personal","five_hour":{"used_percentage":25,"resets_at":1790703000},"seven_day":{"used_percentage":69,"resets_at":1790942400}}
```

They exist only when Claude's `statusLine.command` in settings.json runs through it (`agent-usage-tap ccstatusline`), and they are as fresh as the last response any agent on that account got.
Check them before spawning a batch of workers on an account.

Sidebar keys (for the human): `⏎` jump, `n` new worktree, `o` open project, `d` review, `g` git, `p` pr, `x` kill, `X` remove worktree, `r` rescan, `esc` back, `q` close, `?` help.

New-worktree dialog (`n`):
- Branch name input, a harness list and a `yolo` checkbox. Tab moves between them, j/k move in the list, ⏎ creates from any field, esc cancels.
- The list is `claude codex opencode pi` (or `AGENT_SIDEBAR_HARNESSES`), plus the project's default if missing, plus `no harness` (`none`) last.
- `yolo` appends the harness's flag (see section 4). It is disabled for harnesses without one (`pi`, `none`, custom commands).
- It runs `agent-sidebar-tmux new-worktree <pane> <branch> "<harness> [flag]"`.

### Configuration

Settings live in `${XDG_CONFIG_HOME:-~/.config}/agent-sidebar/config.toml`, linked from `agent-sidebar/.config/agent-sidebar/config.toml` in the dotfiles.
Every setting is optional, and so is the file.
`agent-sidebar-config` is the one reader of it: agent-scan and agent-sidebar load it as a module, and `agent-sidebar-tmux` runs it.

| Setting | Variable | Per project | Read by | Effect |
|---------|----------|-------------|---------|--------|
| `hide` | - | - | agent-scan, sidebar | tmux session names (shell globs allowed) whose agents the sidebar and `agent-scan --tmux` leave out (default `[]`) |
| `harnesses` | `AGENT_SIDEBAR_HARNESSES` | - | sidebar | Harnesses in the dialog; the variable is space or comma separated (default `claude codex opencode pi`) |
| `agent` | `AGENT_SIDEBAR_AGENT` | `git config agent-sidebar.harness` | sidebar, `agent-sidebar-tmux` | Default harness or a whole command (default `claude`); added to the dialog list when not in it |
| `yolo` | `AGENT_SIDEBAR_YOLO` | `git config agent-sidebar.yolo` | sidebar | Default of the yolo checkbox; the variable's `0`/`false`/`no`/`off` turn it off (default on) |
| `width` | `AGENT_SIDEBAR_WIDTH` | - | `agent-sidebar-tmux` | Sidebar width in columns (default `36`) |
| `command` | `AGENT_SIDEBAR_COMMAND` | - | `agent-sidebar-tmux` | Command run in the sidebar pane (default `agent-sidebar`) |

Precedence, first wins: per-project git config > variable > file > default.
The git config keys only affect the dialog; `agent-sidebar-tmux new-worktree` and `spawn` without HARNESS use the variable, then the file.

Hidden agents are still in `agent-scan --json` (`"hidden": true`) and the table, so you can find and message them; only the user's views leave them out.

A file that is not valid TOML, or has an unknown setting or a wrong type, is ignored as a whole until fixed: everything falls back to variables and defaults.
The sidebar shows `config.toml ignored: <error>` in red, the status bar shows `⚠ agent-sidebar config`, and agent-scan warns on stderr.

```bash
agent-sidebar-config check          # silent when fine; prints the error and exits 1 when broken
agent-sidebar-config get hide width # resolved values, one a line (lists space separated)
agent-sidebar-config path           # where the file is
```

## 6. tmux gotchas

- Outside tmux, `tmux` commands (and `agent-scan`) talk to the default server. A server on another socket (`-L`/`-S`) is only reached with `TMUX` set to it: `TMUX="$(tmux -L name display-message -p '#{socket_path},#{pid},0')"`.
- `$TMUX_PANE` is your own pane id.
- `claude` in a folder that neither it nor a parent was trusted in first asks whether to trust it, and Enter picks "No, exit". Worktrees inside a project folder that was trusted inherit that trust.
- `tmux display-message -p -t "%42" '#{pane_current_path}'` gives a pane's cwd.
- `agent-sidebar-tmux follow` is lock-guarded because hooks fire in bursts. Do not call it in a loop.
- A popup that attaches a nested client is a second client; the sidebar ignores server-spawned clients when deciding which window you are viewing.

## 7. Anti-patterns

- Never kill a session, window or pane you did not create for this task, and never the one holding `$TMUX_PANE` - that is the user's. When a `tmux` or `git-wt` command fails, stop and report; do not clean up by killing.
- Do not parse the `agent-scan` table - use `--json`.
- Do not address panes by `target` - it renumbers.
- Do not `send-keys` text without `-l`, or multiline or `;`-ending text without a paste.
- Do not poll `agent-scan` faster than 1s - it walks the process tree and captures every pane.
- Do not judge a pane by its `message` - check `state`. Do not interrupt `running` unless you must.
- Do not call popup actions (`new-worktree`, `review`, `git`, `pr`, `remove-worktree`, `open`) expecting silence - they take over the user's screen.
