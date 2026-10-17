"""Apply backend/migrations/*.sql to MySQL, each file once, in filename order.

Usage, from backend/ with the venv active (settings come from backend/.env):

    python migrate.py            # create the database if needed, apply new files
    python migrate.py --status   # list files and whether each is applied, plus tables

On the Mac, open the tunnel first (scripts/db-tunnel.sh) so DB_HOST=127.0.0.1 works.

Safe to run again: applied files are recorded in `schema_migrations` and skipped.
MySQL commits DDL immediately, so a file is recorded only after every statement in
it succeeded. Write migration files to be re-runnable (CREATE TABLE IF NOT EXISTS)
so a file that failed halfway can simply be fixed and run again.
"""

from __future__ import annotations

import sys
from pathlib import Path

import mysql.connector

from app.config import settings

MIGRATIONS_DIR = Path(__file__).resolve().parent / "migrations"


def split_statements(sql: str) -> list[str]:
    """Split a SQL script on `;`, ignoring semicolons inside quotes and comments.

    Comments are dropped. Handles '...', "...", `...`, -- and # line comments,
    and /* ... */ block comments. Does not support DELIMITER (no procedures).
    """
    statements: list[str] = []
    buf: list[str] = []
    i, n = 0, len(sql)
    quote: str | None = None
    while i < n:
        c = sql[i]
        if quote:
            buf.append(c)
            if c == "\\" and quote != "`" and i + 1 < n:
                buf.append(sql[i + 1])
                i += 2
                continue
            if c == quote:
                if i + 1 < n and sql[i + 1] == quote:  # doubled quote escape
                    buf.append(sql[i + 1])
                    i += 2
                    continue
                quote = None
            i += 1
            continue
        if c in ("'", '"', "`"):
            quote = c
            buf.append(c)
        elif c == "#" or (sql.startswith("--", i) and (i + 2 >= n or sql[i + 2].isspace())):
            nl = sql.find("\n", i)
            i = n if nl == -1 else nl
            continue
        elif sql.startswith("/*", i):
            end = sql.find("*/", i + 2)
            i = n if end == -1 else end + 2
            buf.append(" ")
            continue
        elif c == ";":
            stmt = "".join(buf).strip()
            if stmt:
                statements.append(stmt)
            buf = []
        else:
            buf.append(c)
        i += 1
    if quote:
        raise ValueError(f"unterminated {quote} quote in migration")
    stmt = "".join(buf).strip()
    if stmt:
        statements.append(stmt)
    return statements


def connect():
    # No database yet: it may not exist on a fresh server.
    return mysql.connector.connect(
        host=settings.db_host,
        port=settings.db_port,
        user=settings.db_user,
        password=settings.db_password,
        charset="utf8mb4",
        collation="utf8mb4_0900_ai_ci",
        connection_timeout=10,
        autocommit=True,
    )


def quote_ident(name: str) -> str:
    return "`" + name.replace("`", "``") + "`"


def main(argv: list[str]) -> int:
    status_only = "--status" in argv
    files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    db = quote_ident(settings.db_name)

    print(f"Connecting to {settings.db_user}@{settings.db_host}:{settings.db_port} ...")
    conn = connect()
    cur = conn.cursor()
    cur.execute(f"CREATE DATABASE IF NOT EXISTS {db} CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci")
    cur.execute(f"USE {db}")
    cur.execute(
        "CREATE TABLE IF NOT EXISTS schema_migrations ("
        " filename VARCHAR(255) NOT NULL PRIMARY KEY,"
        " applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP"
        ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    )
    cur.execute("SELECT filename FROM schema_migrations")
    applied = {row[0] for row in cur.fetchall()}

    if status_only:
        for f in files:
            print(f"  [{'x' if f.name in applied else ' '}] {f.name}")
        cur.execute("SHOW TABLES")
        print("Tables:", ", ".join(row[0] for row in cur.fetchall()) or "(none)")
        conn.close()
        return 0

    pending = [f for f in files if f.name not in applied]
    if not pending:
        print(f"Database {settings.db_name} is up to date ({len(files)} migration(s) applied).")
    for f in pending:
        statements = split_statements(f.read_text(encoding="utf-8"))
        print(f"Applying {f.name} ({len(statements)} statements) ...")
        for stmt in statements:
            try:
                cur.execute(stmt)
                if cur.with_rows:
                    cur.fetchall()
            except mysql.connector.Error as exc:
                first_line = stmt.splitlines()[0][:100]
                print(f"FAILED in {f.name} at: {first_line}\n  {exc}", file=sys.stderr)
                conn.close()
                return 1
        cur.execute("INSERT INTO schema_migrations (filename) VALUES (%s)", (f.name,))
        print(f"  applied {f.name}")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
