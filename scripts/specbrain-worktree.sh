#!/usr/bin/env bash
# Worktree lifecycle for specbrain-orchestrate.
#
# Git is local, so this can't live in the MCP server like wave planning does - but it is
# still deterministic, and a sequence of git commands spelled out in prose drifts. Every
# command here refuses rather than improvises, and none of them ever touch the
# repository's main worktree.
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: specbrain-worktree.sh <command> [args]

  main-branch
      Print the repository's main branch (main, else master). Never checks it out.

  create-integration <design-short>
      Create ../specbrain-integration-<design-short> on a new branch
      specbrain/<design-short>, cut from the main branch.

  create-task <design-short> <task-short>
      Create ../specbrain-task-<task-short> on specbrain/task-<task-short>,
      cut from the integration branch.

  merge-task <design-short> <task-short>
      Merge the task branch into the integration branch (--no-ff) and remove the
      task worktree. Refuses if the merge does not apply cleanly, leaving the
      worktree in place to inspect.

  keep-task <design-short> <task-short>
      Print where a failed task's worktree and branch were left.

  integration-path <design-short>
      Print the integration worktree path (for running checks in it).

  cleanup-check
      Exit non-zero if the working tree is dirty.
USAGE
  exit 64
}

require_clean_tree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "specbrain-worktree: working tree is dirty; commit or stash before orchestrating." >&2
    exit 1
  fi
}

main_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo "specbrain-worktree: neither 'main' nor 'master' exists; cannot pick a base branch." >&2
    exit 1
  fi
}

integration_path() { echo "../specbrain-integration-$1"; }
integration_branch() { echo "specbrain/$1"; }
task_path() { echo "../specbrain-task-$1"; }
task_branch() { echo "specbrain/task-$1"; }

cmd="${1:-}"
[ -n "$cmd" ] || usage
shift || true

case "$cmd" in
  main-branch)
    main_branch
    ;;

  cleanup-check)
    require_clean_tree
    echo "clean"
    ;;

  integration-path)
    [ $# -eq 1 ] || usage
    integration_path "$1"
    ;;

  create-integration)
    [ $# -eq 1 ] || usage
    design_short="$1"
    base="$(main_branch)"
    path="$(integration_path "$design_short")"
    branch="$(integration_branch "$design_short")"
    if [ -e "$path" ]; then
      echo "specbrain-worktree: $path already exists; refusing to reuse it blindly." >&2
      exit 1
    fi
    # Cut from the base branch without ever checking it out in the main worktree, so
    # whatever else is using this checkout keeps working during the run.
    git worktree add "$path" -b "$branch" "$base" >&2
    echo "$path"
    ;;

  create-task)
    [ $# -eq 2 ] || usage
    design_short="$1"; task_short="$2"
    integration="$(integration_path "$design_short")"
    path="$(task_path "$task_short")"
    if [ -e "$path" ]; then
      echo "specbrain-worktree: $path already exists; refusing to reuse it blindly." >&2
      exit 1
    fi
    git -C "$integration" worktree add "../${path#../}" -b "$(task_branch "$task_short")" \
      "$(integration_branch "$design_short")" >&2
    echo "$path"
    ;;

  merge-task)
    [ $# -eq 2 ] || usage
    design_short="$1"; task_short="$2"
    integration="$(integration_path "$design_short")"
    if ! git -C "$integration" merge --no-ff --no-edit "$(task_branch "$task_short")" >&2; then
      echo "specbrain-worktree: merge of $(task_branch "$task_short") did not apply cleanly." >&2
      echo "The task worktree is left in place at $(task_path "$task_short") to inspect." >&2
      exit 1
    fi
    git -C "$integration" worktree remove "../specbrain-task-$task_short" >&2
    echo "merged"
    ;;

  keep-task)
    [ $# -eq 2 ] || usage
    echo "worktree=$(task_path "$2") branch=$(task_branch "$2")"
    ;;

  *)
    usage
    ;;
esac
