#!/usr/bin/env bash
set -euo pipefail

# ====== CONFIG (edit if your branch names differ) ======
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
MAIN_BRANCH="${MAIN_BRANCH:-main}"
DEV_BRANCH="${DEV_BRANCH:-sky/dev}"

# Set to 1 if you want the script to auto-stash & pop your local changes.
AUTO_STASH="${AUTO_STASH:-0}"

# ====== HELPERS ======
die() { echo "❌ $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Not inside a git repo."
}

ensure_remote_exists() {
  local r="$1"
  git remote get-url "$r" >/dev/null 2>&1 || die "Remote '$r' not found. Run: git remote -v"
}

ensure_clean_or_stash() {
  if [[ -n "$(git status --porcelain)" ]]; then
    if [[ "$AUTO_STASH" == "1" ]]; then
      info "Working tree not clean — stashing changes..."
      git stash push -u -m "safe-update: $(date -Iseconds)"
      export DID_STASH=1
    else
      die "Working tree not clean. Commit/stash first, or re-run with AUTO_STASH=1"
    fi
  fi
}

restore_stash_if_needed() {
  if [[ "${DID_STASH:-0}" == "1" ]]; then
    info "Restoring stashed changes..."
    # Pop the most recent stash (the one we just created)
    git stash pop || die "Stash pop had conflicts. Resolve manually."
  fi
}

ensure_branch_exists_local() {
  local b="$1"
  git show-ref --verify --quiet "refs/heads/$b" || die "Local branch '$b' not found."
}

fetch_all() {
  info "Fetching remotes..."
  git fetch --prune "$UPSTREAM_REMOTE"
  git fetch --prune "$ORIGIN_REMOTE"
  ok "Fetch complete."
}

update_main_from_upstream() {
  info "Checking out '$MAIN_BRANCH'..."
  git checkout "$MAIN_BRANCH" >/dev/null

  info "Fast-forwarding '$MAIN_BRANCH' to '$UPSTREAM_REMOTE/$MAIN_BRANCH'..."
  # This guarantees main matches upstream with no merge commits
  git reset --hard "$UPSTREAM_REMOTE/$MAIN_BRANCH"
  ok "'$MAIN_BRANCH' now matches '$UPSTREAM_REMOTE/$MAIN_BRANCH'."
}

rebase_dev_onto_main() {
  info "Checking out '$DEV_BRANCH'..."
  git checkout "$DEV_BRANCH" >/dev/null

  info "Rebasing '$DEV_BRANCH' onto '$MAIN_BRANCH'..."
  git rebase "$MAIN_BRANCH" || die "Rebase failed. Fix conflicts, then run: git rebase --continue (or --abort)."
  ok "Rebase successful."
}

push_updates() {
  info "Pushing '$MAIN_BRANCH' to '$ORIGIN_REMOTE/$MAIN_BRANCH'..."
  git push "$ORIGIN_REMOTE" "$MAIN_BRANCH"

  info "Pushing '$DEV_BRANCH' to '$ORIGIN_REMOTE/$DEV_BRANCH' with --force-with-lease (safe rebase push)..."
  git push --force-with-lease "$ORIGIN_REMOTE" "$DEV_BRANCH"
  ok "Push complete."
}

show_summary() {
  echo
  info "Summary:"
  echo "  main: $(git rev-parse --short "$MAIN_BRANCH")  (tracking ${UPSTREAM_REMOTE}/${MAIN_BRANCH})"
  echo "  dev : $(git rev-parse --short "$DEV_BRANCH")"
  echo
  info "Recent commits on dev:"
  git --no-pager log --oneline -n 10
}

# ====== MAIN ======
require_git_repo
ensure_remote_exists "$UPSTREAM_REMOTE"
ensure_remote_exists "$ORIGIN_REMOTE"
ensure_branch_exists_local "$MAIN_BRANCH"
ensure_branch_exists_local "$DEV_BRANCH"

CURRENT_BRANCH="$(git branch --show-current || true)"
info "Current branch: ${CURRENT_BRANCH:-<detached>}"

ensure_clean_or_stash
fetch_all
update_main_from_upstream
rebase_dev_onto_main
push_updates
restore_stash_if_needed
show_summary

ok "Done."
