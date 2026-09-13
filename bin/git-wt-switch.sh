#!/usr/bin/env bash
# git-wt-switch.sh: `git-wt switch` under the name git aliases, the agent sidebar and
# Claude Code settings already use. See git-wt.
exec "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/git-wt" switch "$@"
