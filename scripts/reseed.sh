#!/usr/bin/env bash
# The one command before a demo (S-25). From the Mac:
#   bash scripts/reseed.sh          reseed vanderbilt.edu, delete smoke.edu and orphan uploads,
#                                   print a summary and check the demo campus is clean
#   bash scripts/reseed.sh --check  change nothing: validate the seed data and check the live
#                                   demo campus is still in its seeded state (exit 1 if not)
# Runs backend/seed/reset.py on the server with the code already deployed there, so after
# changing seed data run scripts/deploy.sh first (this warns when the server is behind).
# Idempotent. Demo accounts keep their ids and sessions, so logged-in phones stay logged in.
set -euo pipefail

KEY="${LOOP_SSH_KEY:-$HOME/.ssh/loop-key.pem}"
SERVER="opc@163.192.218.131"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

remote_head="$(ssh -i "$KEY" -o ConnectTimeout=10 "$SERVER" 'git -C ~/loop rev-parse HEAD' 2>/dev/null || true)"
local_head="$(git -C "$ROOT" rev-parse origin/main 2>/dev/null || true)"
if [[ -n "$remote_head" && -n "$local_head" && "$remote_head" != "$local_head" ]]; then
  echo "WARNING: the server is at ${remote_head:0:7}, origin/main is ${local_head:0:7}." >&2
  echo "         If seed data changed, run 'bash scripts/deploy.sh' first." >&2
fi

ssh -i "$KEY" -o ConnectTimeout=10 "$SERVER" "cd ~/loop/backend && .venv/bin/python -m seed.reset $*"
