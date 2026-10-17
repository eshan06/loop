#!/usr/bin/env bash
# Forward a local port to MySQL HeatWave (private IP only) through the OCI server.
# Usage: bash scripts/db-tunnel.sh        (Ctrl-C closes it)
# Then run things from backend/ with DB_HOST=127.0.0.1 and DB_PORT=<local port>.
# Uses local port 3306, or 3307 if 3306 is taken (then set DB_PORT=3307 in backend/.env).
set -euo pipefail

KEY="${LOOP_SSH_KEY:-$HOME/.ssh/loop-key.pem}"
SERVER="opc@163.192.218.131"
MYSQL_HOST="10.0.1.191"

port=3306
if nc -z 127.0.0.1 "$port" 2>/dev/null; then
  port=3307
  echo "Local 3306 is busy, using 3307. Set DB_PORT=3307 in backend/.env."
fi

echo "Tunnel: 127.0.0.1:$port -> $MYSQL_HOST:3306 via $SERVER (Ctrl-C to close)"
exec ssh -i "$KEY" -N \
  -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -L "$port:$MYSQL_HOST:3306" "$SERVER"
