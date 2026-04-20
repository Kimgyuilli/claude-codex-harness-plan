#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/cleanup-smoke-pr.sh --pr <number> --branch <name> --revert <sha> [--revert <sha> ...] [--execute] [--push]

Purpose:
  Close the smoke PR and revert smoke commits after Phase 4a validation.

Behavior:
  - Dry-run by default
  - Requires explicit --execute to perform changes
  - Optional --push will push the revert commits after execution

Example:
  scripts/cleanup-smoke-pr.sh \
    --pr 123 \
    --branch experiment/harness-prototype \
    --revert abcdef1 \
    --revert abcdef2
EOF
}

PR_NUMBER=""
BRANCH_NAME=""
EXECUTE=0
PUSH_AFTER=0
REVERTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR_NUMBER="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH_NAME="${2:-}"
      shift 2
      ;;
    --revert)
      REVERTS+=("${2:-}")
      shift 2
      ;;
    --execute)
      EXECUTE=1
      shift
      ;;
    --push)
      PUSH_AFTER=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PR_NUMBER" || -z "$BRANCH_NAME" || ${#REVERTS[@]} -eq 0 ]]; then
  echo "missing required arguments" >&2
  usage >&2
  exit 2
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "not inside a git repository" >&2
  exit 2
fi

CURRENT_BRANCH="$(git branch --show-current)"

echo "cleanup target:"
echo "  pr: $PR_NUMBER"
echo "  branch: $BRANCH_NAME"
echo "  current_branch: $CURRENT_BRANCH"
echo "  reverts: ${REVERTS[*]}"
echo "  execute: $EXECUTE"
echo "  push_after: $PUSH_AFTER"

if [[ "$CURRENT_BRANCH" != "$BRANCH_NAME" ]]; then
  echo "warning: current branch differs from target branch" >&2
fi

echo
echo "planned commands:"
echo "  gh pr close $PR_NUMBER"
for sha in "${REVERTS[@]}"; do
  echo "  git revert --no-edit $sha"
done
if [[ "$PUSH_AFTER" -eq 1 ]]; then
  echo "  git push origin $BRANCH_NAME"
fi

if [[ "$EXECUTE" -ne 1 ]]; then
  echo
  echo "dry-run only. add --execute to perform cleanup."
  exit 0
fi

gh pr close "$PR_NUMBER"
for sha in "${REVERTS[@]}"; do
  git revert --no-edit "$sha"
done

if [[ "$PUSH_AFTER" -eq 1 ]]; then
  git push origin "$BRANCH_NAME"
fi

echo
echo "cleanup completed."
