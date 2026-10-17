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

# upload FILE KIND [TOKEN] -> POST /photos multipart (file, kind); sets STATUS, body in $BODY.
# FILE "-" sends no file part; KIND "-" sends no kind part.
upload() {
  local file="$1" kind="$2" token="${3:-}"
  local args=(-sS -o "$BODY" -w '%{http_code}' -X POST --max-time 60)
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ "$file" != "-" ]] && args+=(-F "file=@$file;type=image/jpeg")
  [[ "$kind" != "-" ]] && args+=(-F "kind=$kind")
  STATUS="$(curl "${args[@]}" "$BASE_URL/photos")" || STATUS="curl-error"
}

# fetch URL OUTFILE -> sets STATUS and CTYPE (no auth)
fetch() {
  local out
  out="$(curl -sS -o "$2" -w '%{http_code} %{content_type}' --max-time 30 "$1")" || out="curl-error -"
  STATUS="${out%% *}"; CTYPE="${out#* }"
}

# jpeg_size FILE -> prints WIDTHxHEIGHT from the JPEG's SOF marker (stdlib only)
jpeg_size() {
  python3 -c '
import struct, sys
b = open(sys.argv[1], "rb").read()
assert b[:2] == b"\xff\xd8", "not a JPEG"
i = 2
while i < len(b):
    if b[i] != 0xFF: i += 1; continue
    m = b[i + 1]
    if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7: i += 2; continue
    n = struct.unpack(">H", b[i + 2:i + 4])[0]
    if m in (0xC0, 0xC1, 0xC2):
        h, w = struct.unpack(">HH", b[i + 5:i + 9]); print(f"{w}x{h}"); break
    i += 2 + n
' "$1"
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
section "photos (S-9)"
# 64x32 red JPEG with EXIF orientation 6 (displays rotated 90 degrees): the server
# should store it upright as 32x64.
SMALL_JPEG_B64='/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAAgAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDLoooriPpgooooAKKKKACiiigAooooAKKKKACiiigAooooA//Z'
SMALL_JPEG="$TMP/small.jpg"
python3 -c 'import base64, sys; open(sys.argv[2], "wb").write(base64.b64decode(sys.argv[1]))' "$SMALL_JPEG_B64" "$SMALL_JPEG"
NOT_IMAGE="$TMP/notes.txt"
echo "definitely not a photo" > "$NOT_IMAGE"
FAKE_JPEG="$TMP/fake.jpg"
printf '\xff\xd8\xff\xe0 truncated garbage' > "$FAKE_JPEG"
HUGE="$TMP/huge.jpg"
head -c 5300000 /dev/zero > "$HUGE"

upload "$SMALL_JPEG" avatar "$TOKEN_A"
expect 201 "POST /photos kind=avatar"
check 'set(d) == {"id", "url", "kind"} and isinstance(d["id"], int) and d["kind"] == "avatar"' "Photo object: id, url, kind"
check "d['url'].startswith('$BASE_URL/media/') and d['url'].endswith('.jpg')" "url is absolute under /media"
AVATAR_ID="$(jget 'd["id"]')"
AVATAR_URL="$(jget 'd["url"]')"

fetch "$AVATAR_URL" "$TMP/got.jpg"
[[ "$STATUS" == "200" && "$CTYPE" == image/jpeg* ]] || fail "GET photo url (got $STATUS $CTYPE)"
ok "GET photo url without auth: 200 image/jpeg"
[[ "$(jpeg_size "$TMP/got.jpg")" == "32x64" ]] || fail "EXIF orientation applied (got $(jpeg_size "$TMP/got.jpg"))"
ok "EXIF orientation applied (64x32 rotated to 32x64)"

if command -v sips >/dev/null 2>&1 && sips -z 1000 2000 "$SMALL_JPEG" --out "$TMP/big.jpg" >/dev/null 2>&1; then
  upload "$TMP/big.jpg" FRONT "$TOKEN_A"
  expect 201 "POST /photos 2000x1000 kind=FRONT"
  check 'd["kind"] == "front"' "kind normalized to lowercase"
  fetch "$(jget 'd["url"]')" "$TMP/got-big.jpg"
  # sips may carry the EXIF orientation over, so either orientation is fine.
  BIG_SIZE="$(jpeg_size "$TMP/got-big.jpg" 2>/dev/null)"
  [[ "$STATUS" == "200" && ( "$BIG_SIZE" == "1600x800" || "$BIG_SIZE" == "800x1600" ) ]] \
    || fail "big photo resized to longest side 1600 (got $STATUS $BIG_SIZE)"
  ok "big photo resized to longest side 1600"
else
  echo "  skip resize check (no sips)"
fi

upload "$NOT_IMAGE" front "$TOKEN_A"
expect 400 bad_request "POST /photos with a text file"
upload "$FAKE_JPEG" front "$TOKEN_A"
expect 400 bad_request "POST /photos with a broken JPEG"
upload "$HUGE" front "$TOKEN_A"
expect 400 photo_too_large "POST /photos over 5 MB"
upload "$SMALL_JPEG" - "$TOKEN_A"
expect 400 bad_request "POST /photos without kind"
upload "$SMALL_JPEG" sideways "$TOKEN_A"
expect 400 bad_request "POST /photos with an unknown kind"
upload - front "$TOKEN_A"
expect 400 bad_request "POST /photos without a file"
upload "$SMALL_JPEG" front
expect 401 unauthorized "POST /photos without a token"

req PATCH /me "{\"avatar_photo_id\": $AVATAR_ID}" "$TOKEN_B"
expect 400 bad_request "PATCH /me avatar with someone else's photo"
req PATCH /me "{\"avatar_photo_id\": $AVATAR_ID}" "$TOKEN_A"
expect 200 "PATCH /me avatar_photo_id"
check "d['avatar_url'] == '$AVATAR_URL'" "PATCH /me returns the avatar url"
req GET /me "" "$TOKEN_A"
check "d['avatar_url'] == '$AVATAR_URL'" "GET /me shows the avatar url"

# ---------------------------------------------------------------------------
section "meetup spots (S-14)"
req GET /meetup-spots
expect 401 unauthorized "GET /meetup-spots without a token"
req GET /meetup-spots "" "$TOKEN_A"
expect 200 "GET /meetup-spots"
check 'list(d) == ["items"] and len(d["items"]) > 0' "campus has at least one spot (defaults filled in)"
check 'all(set(s) == {"id", "name"} and type(s["id"]) is int and isinstance(s["name"], str) and s["name"] for s in d["items"])' "each spot is {id, name}"
check '[s["name"].casefold() for s in d["items"]] == sorted(s["name"].casefold() for s in d["items"])' "spots sorted by name"
check 'len({s["id"] for s in d["items"]}) == len(d["items"])' "spot ids unique"
SPOTS_A="$(jget '[s["id"] for s in d["items"]]')"
req GET /meetup-spots "" "$TOKEN_B"
expect 200 "GET /meetup-spots as user B (same campus)"
check "[s['id'] for s in d['items']] == $SPOTS_A" "same list for everyone on the campus, no duplicate defaults"

# ---------------------------------------------------------------------------
echo
echo "PASS: $PASS checks against $BASE_URL"
