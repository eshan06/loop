#!/usr/bin/env bash
# End-to-end smoke test of the live API. One growing script: each task adds a section.
# Usage: bash scripts/smoke.sh            (BASE_URL defaults to the live server)
#        BASE_URL=http://127.0.0.1:8000 bash scripts/smoke.sh
# Uses throwaway users on campus smoke.edu. Needs curl and python3 (JSON checks only).
# Exits non-zero at the first failed check.
set -uo pipefail

BASE_URL="${BASE_URL:-http://163.192.218.131:8000}"
BASE_URL="${BASE_URL%/}"
RUN="$(date +%s)$RANDOM"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
BODY="$TMP/body"
PASS=0

fail() {
  echo "FAIL: $*" >&2
  echo "  last response: HTTP $STATUS $(head -c 600 "$BODY" 2>/dev/null)" >&2
  exit 1
}
ok() { PASS=$((PASS + 1)); echo "  ok  $*"; }
section() { echo "== $*"; }

# req METHOD PATH [JSON_BODY] [TOKEN] -> sets STATUS, body in $BODY
req() {
  local method="$1" path="$2" data="${3:-}" token="${4:-}"
  local args=(-sS -o "$BODY" -w '%{http_code}' -X "$method" --max-time 30)
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' --data "$data")
  STATUS="$(curl "${args[@]}" "$BASE_URL$path")" || STATUS="curl-error"
}

# expect STATUS [ERROR_CODE] DESCRIPTION
expect() {
  local want="$1"; shift
  local code=""
  if [[ $# -gt 1 ]]; then code="$1"; shift; fi
  [[ "$STATUS" == "$want" ]] || fail "$* (wanted HTTP $want)"
  if [[ -n "$code" ]]; then
    local got
    got="$(jget 'd["error"]["code"]')" || fail "$* (no error body)"
    [[ "$got" == "$code" ]] || fail "$* (wanted code $code, got $got)"
  fi
  ok "$*"
}

# jget PYTHON_EXPR -> prints eval(expr) with d = parsed body (strings raw, others as JSON)
jget() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
v = eval(sys.argv[2])
print(v if isinstance(v, str) else json.dumps(v))
' "$BODY" "$1"
}

# check PYTHON_BOOL_EXPR DESCRIPTION  (d = parsed body, re and ISO are available)
check() {
  python3 -c '
import json, re, sys
d = json.load(open(sys.argv[1]))
ISO = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
sys.exit(0 if eval(sys.argv[2]) else 1)
' "$BODY" "$1" 2>/dev/null || fail "$2"
  ok "$2"
}

# ---------------------------------------------------------------------------
section "health"
req GET /health
expect 200 "GET /health"
check 'd == {"status": "ok"}' "health body is {status: ok}"

# ---------------------------------------------------------------------------
section "auth and profile (S-8)"
EMAIL_A="Smoke.A${RUN}@Smoke.EDU"
email_a="smoke.a${RUN}@smoke.edu"

req POST /auth/login '{}'
expect 400 bad_request "login without email"
req POST /auth/login '{"email": "someone@gmail.com"}'
expect 400 not_edu_email "login with a non-.edu email"
req POST /auth/login '{"email": "not-an-email.edu"}'
expect 400 not_edu_email "login with no @"

req POST /auth/login "{\"email\": \"  $EMAIL_A  \"}"
expect 200 "login new user A (trimmed, mixed case)"
check 'd["is_new"] is True' "is_new true on first login"
check 'isinstance(d["token"], str) and len(d["token"]) == 32' "token is 32 chars"
check "d['user']['email'] == '$email_a'" "email trimmed and lowercased"
check 'd["user"]["campus"]["name"] == "Smoke"' "campus named from domain"
check 'all(d["user"][k] is None for k in ("name","dorm","class_year","avatar_url"))' "new user nullable fields are null"
check 'd["user"]["sizes"] == {"top": None, "bottom": None, "shoe": None}' "sizes object with nulls"
check 'd["user"]["items_shared"] == 0 and ISO.match(d["user"]["created_at"])' "items_shared 0, created_at ISO Z"
TOKEN_A="$(jget 'd["token"]')"
USER_A="$(jget 'd["user"]["id"]')"
CAMPUS="$(jget 'd["user"]["campus"]["id"]')"

req POST /auth/login "{\"email\": \"$email_a\"}"
expect 200 "login A again"
check "d['is_new'] is False and d['user']['id'] == $USER_A and d['token'] != '$TOKEN_A'" "same user, not new, new token"
TOKEN_A2="$(jget 'd["token"]')"

req POST /auth/login "{\"email\": \"smoke.b${RUN}@alumni.smoke.edu\"}"
expect 200 "login user B on a subdomain"
check "d['user']['campus']['id'] == $CAMPUS and d['user']['id'] != $USER_A" "subdomain lands on the same campus"
TOKEN_B="$(jget 'd["token"]')"

req GET /me
expect 401 unauthorized "GET /me without a token"
req GET /me "" "nope-not-a-token"
expect 401 unauthorized "GET /me with a bad token"
req GET /me "" "$TOKEN_A"
expect 200 "GET /me with the first token (old tokens keep working)"
check "d['id'] == $USER_A and d['email'] == '$email_a'" "GET /me returns user A"
req GET /me "" "$TOKEN_A2"
expect 200 "GET /me with the second token"

req GET /dorms "" "$TOKEN_A"
expect 200 "GET /dorms"
check 'd == {"items": []}' "smoke.edu has no dorm list"

req PATCH /me '{"name": "  Smoke Tester ", "dorm": "Smoke Hall", "class_year": 2028, "sizes": {"top": "M", "bottom": "30", "shoe": "9"}}' "$TOKEN_A"
expect 200 "PATCH /me full profile"
check 'd["name"] == "Smoke Tester" and d["dorm"] == "Smoke Hall" and d["class_year"] == 2028' "name trimmed, dorm free text, class_year set"
check 'd["sizes"] == {"top": "M", "bottom": "30", "shoe": "9"}' "sizes set"
req GET /me "" "$TOKEN_A"
check 'd["name"] == "Smoke Tester" and d["sizes"]["shoe"] == "9"' "GET /me shows the saved profile"

req PATCH /me '{"sizes": {"top": "S"}, "dorm": null, "class_year": null}' "$TOKEN_A"
expect 200 "PATCH /me clear fields"
check 'd["sizes"] == {"top": "S", "bottom": None, "shoe": None} and d["dorm"] is None and d["class_year"] is None' "sizes replaced whole, dorm and class_year cleared"
check 'd["name"] == "Smoke Tester"' "unsent name unchanged"

req PATCH /me '{"name": null}' "$TOKEN_A"
expect 400 bad_request "PATCH /me name null"
req PATCH /me '{"name": "   "}' "$TOKEN_A"
expect 400 bad_request "PATCH /me blank name"
req PATCH /me "{\"name\": \"$(printf 'x%.0s' {1..81})\"}" "$TOKEN_A"
expect 400 bad_request "PATCH /me name over 80"
req PATCH /me '{"class_year": 28}' "$TOKEN_A"
expect 400 bad_request "PATCH /me two-digit class_year"
req PATCH /me '{"class_year": "2028"}' "$TOKEN_A"
expect 400 bad_request "PATCH /me class_year as a string"
req PATCH /me '{"sizes": {"top": "XXXXXXXXXXXXXXXXX"}}' "$TOKEN_A"
expect 400 bad_request "PATCH /me size over 16"
req PATCH /me '{"avatar_photo_id": 999999999}' "$TOKEN_A"
expect 400 bad_request "PATCH /me avatar that isn't my photo"
req PATCH /me '{"avatar_photo_id": null}' "$TOKEN_A"
expect 200 "PATCH /me avatar null"
check 'd["avatar_url"] is None' "avatar cleared"
req PATCH /me '{"name": "x"}'
expect 401 unauthorized "PATCH /me without a token"

req GET /me/unread "" "$TOKEN_B"
expect 200 "GET /me/unread"
check 'd == {"notifications": 0, "messages": 0, "incoming_requests": 0}' "new user has nothing unread"
req GET /me/unread
expect 401 unauthorized "GET /me/unread without a token"

# ---------------------------------------------------------------------------
echo
echo "PASS: $PASS checks against $BASE_URL"
