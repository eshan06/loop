#!/usr/bin/env bash
# Deploy main to the OCI server from the Mac: pull, install deps, migrate, restart, check /health.
# Usage: bash scripts/deploy.sh   (push your commits first; the server pulls from GitHub)
# The API is down for a few seconds during the restart.
set -euo pipefail

KEY="${LOOP_SSH_KEY:-$HOME/.ssh/loop-key.pem}"
SERVER="opc@163.192.218.131"
BASE_URL="http://163.192.218.131:8000"

echo "== Deploying to $SERVER"
ssh -i "$KEY" -o ConnectTimeout=10 "$SERVER" 'bash -s' <<'REMOTE'
set -euo pipefail
cd ~/loop
echo "== git pull"
git pull --ff-only
echo "== pip install"
backend/.venv/bin/pip install -q -r backend/requirements.txt
# New or upgraded scripts in .venv/bin get user_home_t; relabel to bin_t or systemd gets 203/EXEC.
sudo restorecon -R backend/.venv/bin
echo "== migrate"
(cd backend && .venv/bin/python migrate.py)
if ! cmp -s scripts/loop-api.service /etc/systemd/system/loop-api.service; then
  echo "== unit file changed, reinstalling"
  sudo cp scripts/loop-api.service /etc/systemd/system/loop-api.service
  sudo systemctl daemon-reload
fi
echo "== restart loop-api"
sudo systemctl restart loop-api
REMOTE

echo "== Waiting for $BASE_URL/health"
for i in $(seq 1 15); do
  if out=$(curl -fsS --max-time 3 "$BASE_URL/health" 2>/dev/null); then
    echo "OK after ${i} tries: $out"
    exit 0
  fi
  sleep 1
done
echo "FAILED: /health did not answer. On the server: sudo journalctl -u loop-api -n 50" >&2
exit 1
