#!/usr/bin/env bash
# Reset the Vanderbilt demo campus on the OCI server to its clean seeded state.
# Usage: bash scripts/reseed.sh          (runs backend/seed/reset.py on the server)
#        bash scripts/reseed.sh --check  (validate the seed data only, change nothing)
# Uses the code already on the server: run scripts/deploy.sh first if seed data changed.
# Seed accounts keep their ids and sessions; other vanderbilt.edu users are deleted.
set -euo pipefail

KEY="${LOOP_SSH_KEY:-$HOME/.ssh/loop-key.pem}"
SERVER="opc@163.192.218.131"

ssh -i "$KEY" -o ConnectTimeout=10 "$SERVER" "cd ~/loop/backend && .venv/bin/python -m seed.reset $*"
