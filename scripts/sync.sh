#!/usr/bin/env bash
# Pull the latest main and show what the other lane has been doing.
# Usage: bash scripts/sync.sh   (reads your lane from .lane)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

lane="$(tr -d '[:space:]' < .lane 2>/dev/null || true)"
if [[ "$lane" != "ios" && "$lane" != "server" ]]; then
  echo "Set this machine's lane first:  echo ios > .lane   or   echo server > .lane"
  exit 1
fi
if [[ "$lane" == "ios" ]]; then other="server"; prefix="I"; else other="ios"; prefix="S"; fi

before="$(git rev-parse HEAD)"
git pull --rebase --autostash --quiet
after="$(git rev-parse HEAD)"

echo "== Lane: $lane"
if [[ "$before" == "$after" ]]; then
  echo "== Already up to date"
else
  echo "== New commits:"
  git log --oneline "$before..$after"
  if ! git diff --quiet "$before" "$after" -- docs/API.md; then
    echo
    echo "!! docs/API.md changed. Read this before writing any networking code:"
    git --no-pager diff "$before" "$after" -- docs/API.md
  fi
fi

echo
echo "== Latest from the $other lane (coord/$other.md):"
awk '/^## Log/{flag=1; next} flag && /^### /{count++} flag && count<=1' "coord/$other.md"

echo
echo "== Requests in coord/$other.md that may be waiting on you:"
awk '/^## Open requests/{flag=1; next} /^## /{flag=0} flag && /^(- |None)/' "coord/$other.md"

echo
echo "== Your open tasks in PLAN.md:"
grep -nE "^- \[( |~|!)\] ${prefix}-[0-9]+" PLAN.md | head -n 12 || echo "None. Check PLAN.md for the next phase."
