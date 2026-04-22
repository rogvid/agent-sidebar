#!/usr/bin/env bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=git-wt-common.sh
source "${SCRIPT_DIR}/git-wt-common.sh"

usage() {
  cat <<EOF
Usage: git-wt-switch.sh [OPTIONS] [branch-name|path]

Switch to an existing worktree.

OPTIONS:
  -t            Open/switch in tmux (when outside tmux)
  -h, --help    Show this help message

EXAMPLES:
  git-wt-switch.sh                 # Select worktree interactively (fzf)
  git-wt-switch.sh feat/new-ui     # Switch by branch name
  git-wt-switch.sh dotfiles-fix-a  # Switch by worktree folder name
  git-wt-switch.sh -t feat/new-ui  # Switch in tmux session
EOF
  exit 0
}

OPEN_TMUX=false
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      ;;
    -t)
      OPEN_TMUX=true
      shift
      ;;
    -*)
      error "Unknown option: $1"
      usage
      ;;
    *)
      if [[ -z "${TARGET}" ]]; then
        TARGET="$1"
      else
        error "Too many arguments"
        usage
      fi
      shift
      ;;
  esac
done

validate_in_git_repo

# Always resolve to the primary repo root even when run from a linked worktree
REPO_ROOT="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"

get_worktree_list() {
  local current_wt=""
  local current_branch=""

  while IFS= read -r line; do
    if [[ "${line}" =~ ^worktree\ (.+)$ ]]; then
      if [[ -n "${current_wt}" ]] && [[ "${current_wt}" != "${REPO_ROOT}" ]]; then
        printf '%s|%s\n' "${current_wt}" "${current_branch}"
      fi
      current_wt="${BASH_REMATCH[1]}"
      current_branch=""
    elif [[ "${line}" =~ ^branch\ refs/heads/(.+)$ ]]; then
      current_branch="${BASH_REMATCH[1]}"
    fi
  done < <(git worktree list --porcelain)

  if [[ -n "${current_wt}" ]] && [[ "${current_wt}" != "${REPO_ROOT}" ]]; then
    printf '%s|%s\n' "${current_wt}" "${current_branch}"
  fi
}

find_worktree() {
  local search="$1"

  while IFS='|' read -r wt_path wt_branch; do
    if [[ "${wt_branch}" == "${search}" ]] || [[ "${wt_path}" == "${search}" ]] || [[ "$(basename "${wt_path}")" == "${search}" ]]; then
      printf '%s|%s\n' "${wt_path}" "${wt_branch}"
      return 0
    fi
  done < <(get_worktree_list)

  return 1
}

select_worktree_interactive() {
  if ! command -v fzf >/dev/null 2>&1; then
    error "fzf is required for interactive mode"
    echo "Install fzf or pass a branch/path argument directly." >&2
    exit 1
  fi

  local worktree_list
  worktree_list="$(get_worktree_list)"

  if [[ -z "${worktree_list}" ]]; then
    echo "No linked worktrees found."
    exit 0
  fi

  local fzf_input=""
  while IFS='|' read -r wt_path wt_branch; do
    local wt_name
    wt_name="$(basename "${wt_path}")"
    fzf_input+="${wt_branch}  [${wt_name}]"$'\t'"${wt_branch}"$'\t'"${wt_path}"$'\n'
  done <<< "${worktree_list}"

  local selected
  selected="$(printf '%s' "${fzf_input}" | fzf --delimiter=$'\t' --with-nth=1 --header='Select worktree:')"

  if [[ -z "${selected}" ]]; then
    exit 0
  fi

  printf '%s|%s\n' "$(printf '%s' "${selected}" | cut -f3)" "$(printf '%s' "${selected}" | cut -f2)"
}

session_name_for_path() {
  local wt_path="$1"
  basename "${wt_path}" | tr '.' '_'
}

switch_to_tmux_session() {
  local wt_path="$1"
  local session_name
  session_name="$(session_name_for_path "${wt_path}")"

  if tmux has-session -t="${session_name}" 2>/dev/null; then
    if [[ -n "${TMUX:-}" ]]; then
      exec tmux switch-client -t "${session_name}"
    else
      exec tmux attach-session -t "${session_name}"
    fi
  fi

  if [[ -n "${TMUX:-}" ]]; then
    tmux new-session -ds "${session_name}" -c "${wt_path}"
    exec tmux switch-client -t "${session_name}"
  else
    exec tmux new-session -s "${session_name}" -c "${wt_path}"
  fi
}

TARGET_INFO=""
if [[ -n "${TARGET}" ]]; then
  if ! TARGET_INFO="$(find_worktree "${TARGET}")"; then
    error "Worktree not found: ${TARGET}"
    echo ""
    echo "Available worktrees:"
    while IFS='|' read -r wt_path wt_branch; do
      echo "  - ${wt_branch} ($(basename "${wt_path}"))"
    done < <(get_worktree_list)
    exit 1
  fi
else
  TARGET_INFO="$(select_worktree_interactive)"
fi

WORKTREE_PATH="${TARGET_INFO%%|*}"
WORKTREE_BRANCH="${TARGET_INFO##*|}"

info "Switching to worktree: ${WORKTREE_BRANCH}"
echo "  Path: ${WORKTREE_PATH}"

if [[ -n "${TMUX:-}" ]]; then
  switch_to_tmux_session "${WORKTREE_PATH}"
fi

if [[ "${OPEN_TMUX}" == true ]]; then
  switch_to_tmux_session "${WORKTREE_PATH}"
fi

cd "${WORKTREE_PATH}"
exec "${SHELL:-/bin/bash}"
