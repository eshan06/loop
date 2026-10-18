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

# req METHOD PATH [JSON_BODY] [TOKEN] -> sets STATUS and SECS (total time), body in $BODY
req() {
  local method="$1" path="$2" data="${3:-}" token="${4:-}" out
  local args=(-sS -o "$BODY" -w '%{http_code} %{time_total}' -X "$method" --max-time 30)
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' --data "$data")
  out="$(curl "${args[@]}" "$BASE_URL$path")" || out="curl-error 0"
  STATUS="${out%% *}"; SECS="${out##* }"
}

# faster_than SECONDS -> true if the last req took less than SECONDS
faster_than() { python3 -c 'import sys; sys.exit(0 if float(sys.argv[1]) < float(sys.argv[2]) else 1)' "$SECS" "$1"; }

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
check 'all(set(s) == {"id", "name", "lat", "lng"} and type(s["id"]) is int and isinstance(s["name"], str) and s["name"] for s in d["items"])' "each spot is {id, name, lat, lng}"
check 'all(s["lat"] is None and s["lng"] is None for s in d["items"])' "a new campus's default spots have null coordinates (S-27)"
check '[s["name"].casefold() for s in d["items"]] == sorted(s["name"].casefold() for s in d["items"])' "spots sorted by name"
check 'len({s["id"] for s in d["items"]}) == len(d["items"])' "spot ids unique"
SPOTS_A="$(jget '[s["id"] for s in d["items"]]')"
req GET /meetup-spots "" "$TOKEN_B"
expect 200 "GET /meetup-spots as user B (same campus)"
check "[s['id'] for s in d['items']] == $SPOTS_A" "same list for everyone on the campus, no duplicate defaults"

# ---------------------------------------------------------------------------
section "listings (S-11)"
MK="mk${RUN}"
SPOT1="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0])' "$SPOTS_A")"

# up FILE KIND TOKEN -> uploads a photo and prints its id (fails the run on error)
up() {
  upload "$1" "$2" "$3"
  [[ "$STATUS" == "201" ]] || fail "upload $2 photo for a listing"
  jget 'd["id"]'
}
P1="$(up "$SMALL_JPEG" front "$TOKEN_A")" || exit 1
P2="$(up "$SMALL_JPEG" back "$TOKEN_A")" || exit 1
P3="$(up "$SMALL_JPEG" label "$TOKEN_A")" || exit 1
P4="$(up "$SMALL_JPEG" front "$TOKEN_A")" || exit 1
P5="$(up "$SMALL_JPEG" front "$TOKEN_A")" || exit 1
P6="$(up "$SMALL_JPEG" other "$TOKEN_A")" || exit 1
PB="$(up "$SMALL_JPEG" front "$TOKEN_B")" || exit 1
ok "uploaded 6 photos for A and 1 for B"

# A user on another campus, for the 404 and spot checks.
req POST /auth/login "{\"email\": \"smoke.c${RUN}@smokeother.edu\"}"
expect 200 "login user C on another campus"
TOKEN_C="$(jget 'd["token"]')"
req GET /meetup-spots "" "$TOKEN_C"
SPOT_C="$(jget 'd["items"][0]["id"]')"

LISTING_KEYS='{"id","title","category","size","color","brand","condition","condition_note","description","tags","share_type","status","photos","meetup_spot","owner","impact","is_mine","saved_by_me","my_request_status","my_request_id","pending_request_count","accepted_request_id","created_at"}'

req POST /listings "{\"title\": \"  Smoke trucker jacket $MK \", \"category\": \"outerwear\", \"size\": \"M\", \"color\": \"Light wash blue\", \"brand\": \"Levis\", \"condition\": \"good\", \"description\": \"Classic trucker jacket.\", \"tags\": [\"denim\", \" jacket \", \"tagonly${RUN}\"], \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P1, $P2, $P3]}" "$TOKEN_A"
expect 201 "POST /listings full body"
check "set(d) == $LISTING_KEYS" "Listing has exactly the contract keys"
check "d['title'] == 'Smoke trucker jacket $MK' and d['category'] == 'outerwear' and d['size'] == 'M' and d['brand'] == 'Levis' and d['condition'] == 'good' and d['share_type'] == 'swap'" "fields saved, title trimmed"
check "d['tags'] == ['denim', 'jacket', 'tagonly${RUN}']" "tags trimmed, in order"
check "d['status'] == 'active' and ISO.match(d['created_at'])" "starts active, created_at ISO Z"
check "[p['id'] for p in d['photos']] == [$P1, $P2, $P3] and [p['kind'] for p in d['photos']] == ['front', 'back', 'label']" "photos attached in order with kinds"
check "all(p['url'].startswith('$BASE_URL/media/') for p in d['photos'])" "photo urls absolute"
check "d['meetup_spot']['id'] == $SPOT1 and isinstance(d['meetup_spot']['name'], str)" "meetup_spot object"
check "set(d['meetup_spot']) == {'id', 'name', 'lat', 'lng'}" "listing's meetup_spot has lat/lng keys (S-27)"
check "d['owner'] == {'id': $USER_A, 'name': 'Smoke Tester', 'dorm': None, 'avatar_url': '$AVATAR_URL', 'items_shared': 0}" "owner is A as an Owner"
check "set(d['impact']) == {'textile_kg', 'water_l', 'co2_kg'} and all(isinstance(v, (int, float)) and v > 0 for v in d['impact'].values())" "impact numbers"
check "d['is_mine'] is True and d['saved_by_me'] is False and d['my_request_status'] is None and d['my_request_id'] is None" "is_mine true, no request, not saved"
check "d['pending_request_count'] == 0 and d['accepted_request_id'] is None" "owner counts empty"
L1="$(jget 'd["id"]')"

req POST /listings "{\"title\": \"Smoke tee $MK\", \"category\": \"TOPS\", \"size\": \"s\", \"condition\": \"like_new\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P4]}" "$TOKEN_A"
expect 201 "POST /listings required fields only"
check "d['color'] is None and d['brand'] is None and d['condition_note'] is None and d['description'] is None and d['tags'] == []" "optional fields null, tags []"
check "d['category'] == 'tops' and len(d['photos']) == 1" "enum lowercased, one photo"
L2="$(jget 'd["id"]')"

req POST /listings "{\"title\": \"Smoke sneakers $MK\", \"category\": \"shoes\", \"size\": \"9\", \"brand\": \"Brandonly${RUN}\", \"condition\": \"worn\", \"share_type\": \"donate\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P5]}" "$TOKEN_A"
expect 201 "POST /listings third listing"
L3="$(jget 'd["id"]')"

# Validation
base="\"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1"
req POST /listings "{$base, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings without title"
req POST /listings "{\"title\": \"$(printf 'x%.0s' {1..121})\", $base, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings title over 120"
req POST /listings "{\"title\": 5, $base, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings title not a string"
req POST /listings "{\"title\": \"x\", \"category\": \"hats\", \"condition\": \"good\", \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings unknown category"
req POST /listings "{\"title\": \"x\", \"category\": \"tops\", \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings without condition"
req POST /listings "{\"title\": \"x\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"sell\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings unknown share_type"
req POST /listings "{\"title\": \"x\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"swap\", \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings without meetup_spot_id"
req POST /listings "{\"title\": \"x\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT_C, \"photo_ids\": [$P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with another campus's meetup spot"
req POST /listings "{\"title\": \"x\", $base}" "$TOKEN_A"
expect 400 bad_request "POST /listings without photo_ids"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": []}" "$TOKEN_A"
expect 400 bad_request "POST /listings with empty photo_ids"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6, $P6, $P6, $P6, $P6, $P6]}" "$TOKEN_A"
expect 400 too_many_photos "POST /listings with 6 photos"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6, $P6]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with a duplicate photo"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6, $P1]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with a photo already on another listing"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$PB]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with someone else's photo"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [999999999]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with a missing photo"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6], \"tags\": [\"a\",\"b\",\"c\",\"d\",\"e\",\"f\",\"g\",\"h\",\"i\",\"j\",\"k\"]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with 11 tags"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6], \"tags\": [\"$(printf 't%.0s' {1..31})\"]}" "$TOKEN_A"
expect 400 bad_request "POST /listings with a 31-char tag"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6], \"size\": \"$(printf 's%.0s' {1..21})\"}" "$TOKEN_A"
expect 400 bad_request "POST /listings size over 20"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6], \"description\": \"$(printf 'd%.0s' {1..2001})\"}" "$TOKEN_A"
expect 400 bad_request "POST /listings description over 2000"
req POST /listings "{\"title\": \"x\", $base, \"photo_ids\": [$P6]}"
expect 401 unauthorized "POST /listings without a token"

# Feed, as B (same campus). Every check narrows to this run's listings with q=$MK.
req GET "/listings?q=$MK" "" "$TOKEN_B"
expect 200 "GET /listings as B"
check "set(d) == {'items', 'total', 'next_offset'} and d['total'] == 3 and d['next_offset'] is None" "paged shape, B sees A's 3 listings"
check "[x['id'] for x in d['items']] == [$L3, $L2, $L1]" "newest first"
check "all(x['is_mine'] is False and x['pending_request_count'] == 0 and x['accepted_request_id'] is None for x in d['items'])" "is_mine false for B, owner counts hidden"
check "all(set(x) == $LISTING_KEYS for x in d['items'])" "feed items are full Listings"
req GET "/listings?q=$MK" "" "$TOKEN_A"
check "d['total'] == 3 and all(x['is_mine'] for x in d['items'])" "own listings included in A's feed with is_mine true"
req GET "/listings" "" "$TOKEN_B"
expect 200 "GET /listings without filters"
check "d['total'] >= 3 and len(d['items']) <= 20 and all(x['status'] == 'active' for x in d['items'])" "default page of active listings"
req GET "/listings?q=$MK&share_type=free" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L2]" "filter share_type=free"
req GET "/listings?q=$MK&category=shoes" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L3]" "filter category=shoes"
req GET "/listings?q=$MK&size=m" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L1]" "filter size, case-insensitive"
req GET "/listings?q=$MK&share_type=swap&category=tops" "" "$TOKEN_B"
check "d == {'items': [], 'total': 0, 'next_offset': None}" "combined filters with no match"
req GET "/listings?q=TAGONLY${RUN}" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L1]" "search matches tags, case-insensitive"
req GET "/listings?q=brandonly${RUN}" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L3]" "search matches brand"
req GET "/listings?q=Sneakers%20$MK" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L3]" "search matches title substring"
req GET "/listings?q=%25$MK" "" "$TOKEN_B"
check "d['total'] == 0" "a % in q is literal, not a wildcard"
req GET "/listings?share_type=sell" "" "$TOKEN_B"
expect 400 bad_request "unknown share_type filter"
req GET "/listings?category=hats" "" "$TOKEN_B"
expect 400 bad_request "unknown category filter"
req GET "/listings?q=$MK&limit=2" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L3, $L2] and d['total'] == 3 and d['next_offset'] == 2" "page 1 of 2"
req GET "/listings?q=$MK&limit=2&offset=2" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L1] and d['next_offset'] is None" "page 2 of 2"
req GET "/listings?q=$MK&offset=10" "" "$TOKEN_B"
check "d['items'] == [] and d['total'] == 3 and d['next_offset'] is None" "offset past the end"
req GET "/listings?limit=0" "" "$TOKEN_B"
expect 400 bad_request "limit=0"
req GET "/listings?limit=abc" "" "$TOKEN_B"
expect 400 bad_request "limit not a number"
req GET "/listings?limit=500" "" "$TOKEN_B"
expect 200 "limit over 50 is capped"
check "len(d['items']) <= 50" "at most 50 items"
req GET /listings
expect 401 unauthorized "GET /listings without a token"
req GET "/listings?q=$MK" "" "$TOKEN_C"
check "d['total'] == 0" "another campus doesn't see them"

# Detail
req GET "/listings/$L1" "" "$TOKEN_B"
expect 200 "GET /listings/{id} as B"
check "d['id'] == $L1 and d['is_mine'] is False and [p['id'] for p in d['photos']] == [$P1, $P2, $P3]" "detail as B"
req GET "/listings/$L1" "" "$TOKEN_C"
expect 404 not_found "GET /listings/{id} from another campus"
req GET "/listings/999999999" "" "$TOKEN_B"
expect 404 not_found "GET /listings/{id} that doesn't exist"

# Edit and delete permissions
req PATCH "/listings/$L1" '{"title": "hijacked"}' "$TOKEN_B"
expect 403 forbidden "B can't PATCH A's listing"
req DELETE "/listings/$L1" "" "$TOKEN_B"
expect 403 forbidden "B can't DELETE A's listing"
req PATCH "/listings/$L1" '{"title": "hijacked"}' "$TOKEN_C"
expect 404 not_found "PATCH from another campus is 404"

req PATCH "/listings/$L1" "{\"title\": \"Smoke trucker jacket edited $MK\", \"brand\": null, \"photo_ids\": [$P3, $P1]}" "$TOKEN_A"
expect 200 "A PATCHes title, clears brand, reorders photos"
check "d['title'] == 'Smoke trucker jacket edited $MK' and d['brand'] is None" "title changed, brand cleared"
check "d['size'] == 'M' and d['color'] == 'Light wash blue' and d['tags'] == ['denim', 'jacket', 'tagonly${RUN}']" "unsent fields unchanged"
check "[p['id'] for p in d['photos']] == [$P3, $P1]" "photos replaced in the new order"
req GET "/listings/$L1" "" "$TOKEN_B"
check "[p['id'] for p in d['photos']] == [$P3, $P1] and d['brand'] is None" "GET shows the edit"
req PATCH "/listings/$L2" "{\"photo_ids\": [$P4, $P2], \"share_type\": \"swap\", \"tags\": [\"tee\"]}" "$TOKEN_A"
expect 200 "a photo removed from one listing can go on another"
check "[p['id'] for p in d['photos']] == [$P4, $P2] and d['share_type'] == 'swap' and d['tags'] == ['tee']" "L2 photos, share_type, tags updated"
req PATCH "/listings/$L2" '{}' "$TOKEN_A"
expect 200 "PATCH with an empty body"
req PATCH "/listings/$L2" '{"title": "  "}' "$TOKEN_A"
expect 400 bad_request "PATCH blank title"
req PATCH "/listings/$L2" '{"category": null}' "$TOKEN_A"
expect 400 bad_request "PATCH category null"
req PATCH "/listings/$L2" '{"meetup_spot_id": null}' "$TOKEN_A"
expect 400 bad_request "PATCH meetup_spot_id null"
req PATCH "/listings/$L2" '{"photo_ids": []}' "$TOKEN_A"
expect 400 bad_request "PATCH photo_ids empty"
req PATCH "/listings/$L2" "{\"photo_ids\": [$P3]}" "$TOKEN_A"
expect 400 bad_request "PATCH with a photo on another listing"
req PATCH "/listings/$L2" '{"condition": "mint"}' "$TOKEN_A"
expect 400 bad_request "PATCH unknown condition"
req PATCH "/listings/999999999" '{"title": "x"}' "$TOKEN_A"
expect 404 not_found "PATCH a listing that doesn't exist"

# condition_note (S-28): optional, trimmed, empty -> null, max 140
req PATCH "/listings/$L2" '{"condition_note": "  small pill on the left sleeve  "}' "$TOKEN_A"
expect 200 "PATCH condition_note"
check "d['condition_note'] == 'small pill on the left sleeve' and d['condition'] == 'like_new'" "condition_note trimmed, condition unchanged"
req GET "/listings/$L2" "" "$TOKEN_B"
check "d['condition_note'] == 'small pill on the left sleeve'" "GET shows the condition_note to B"
req PATCH "/listings/$L2" '{"title": "Smoke tee '"$MK"'"}' "$TOKEN_A"
check "d['condition_note'] == 'small pill on the left sleeve'" "PATCH without condition_note keeps it"
req PATCH "/listings/$L2" '{"condition_note": "   "}' "$TOKEN_A"
expect 200 "PATCH blank condition_note"
check "d['condition_note'] is None" "blank condition_note becomes null"
NOTE141="$(python3 -c 'print("x" * 141)')"
req PATCH "/listings/$L2" "{\"condition_note\": \"$NOTE141\"}" "$TOKEN_A"
expect 400 bad_request "PATCH condition_note over 140 characters"
req PATCH "/listings/$L2" "{\"condition_note\": \"${NOTE141:1}\"}" "$TOKEN_A"
expect 200 "PATCH condition_note of exactly 140 characters"
check "len(d['condition_note']) == 140" "140-character condition_note saved"
req PATCH "/listings/$L2" '{"condition_note": 5}' "$TOKEN_A"
expect 400 bad_request "PATCH condition_note that isn't a string"
req PATCH "/listings/$L2" '{"condition_note": null}' "$TOKEN_A"
expect 200 "PATCH condition_note null"
check "d['condition_note'] is None" "condition_note cleared"
# Create with a note as a fresh user, so A's listing count (badges, S-22) stays as before.
req POST /auth/login "{\"email\": \"smoke.n${RUN}@smoke.edu\"}"
expect 200 "login note tester N"
TOKEN_N="$(jget 'd["token"]')"
PN="$(up "$SMALL_JPEG" front "$TOKEN_N")" || exit 1
NOTE_POST="\"title\": \"Smoke noted cap $RUN\", \"category\": \"accessories\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$PN]"
req POST /listings "{$NOTE_POST, \"condition_note\": \"$NOTE141\"}" "$TOKEN_N"
expect 400 bad_request "POST /listings with a condition_note over 140 characters"
req POST /listings "{$NOTE_POST, \"condition_note\": \"  \"}" "$TOKEN_N"
expect 201 "POST /listings with a blank condition_note"
check "d['condition_note'] is None" "blank condition_note on create is null"
req DELETE "/listings/$(jget 'd["id"]')" "" "$TOKEN_N"
expect 204 "clean up"
req POST /listings "{$NOTE_POST, \"condition_note\": \" light fading on the brim \"}" "$TOKEN_N"
expect 201 "POST /listings with a condition_note"
check "d['condition_note'] == 'light fading on the brim'" "condition_note trimmed and saved on create"
req GET "/listings/$(jget 'd["id"]')" "" "$TOKEN_B"
check "d['condition_note'] == 'light fading on the brim' and d['condition'] == 'good'" "B sees the note on detail"
req DELETE "/listings/$(jget 'd["id"]')" "" "$TOKEN_N"
expect 204 "clean up"

# My listings
req GET /me/listings "" "$TOKEN_A"
expect 200 "GET /me/listings"
check "[x['id'] for x in d['items']] == [$L3, $L2, $L1] and d['total'] == 3 and d['next_offset'] is None" "A's active listings, newest first"
req GET "/me/listings?status=active&limit=1&offset=1" "" "$TOKEN_A"
check "[x['id'] for x in d['items']] == [$L2] and d['next_offset'] == 2" "my listings paged"
req GET "/me/listings?status=completed" "" "$TOKEN_A"
expect 200 "GET /me/listings?status=completed"
check "d == {'items': [], 'total': 0, 'next_offset': None}" "no completed listings yet"
req GET "/me/listings?status=sold" "" "$TOKEN_A"
expect 400 bad_request "GET /me/listings unknown status"
req GET /me/listings "" "$TOKEN_B"
check "d['total'] == 0" "B has no listings"

# Delete
req DELETE "/listings/$L3" "" "$TOKEN_A"
expect 204 "A DELETEs a listing"
req GET "/listings/$L3" "" "$TOKEN_A"
expect 404 not_found "deleted listing is gone"
req DELETE "/listings/$L3" "" "$TOKEN_A"
expect 404 not_found "DELETE again is 404"
req GET "/listings?q=$MK" "" "$TOKEN_B"
check "[x['id'] for x in d['items']] == [$L2, $L1]" "feed no longer has it"
req POST /listings "{\"title\": \"Smoke sneakers again $MK\", \"category\": \"shoes\", \"condition\": \"worn\", \"share_type\": \"donate\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P5]}" "$TOKEN_A"
expect 201 "a deleted listing's photo can be reused"
L4="$(jget 'd["id"]')"
req DELETE "/listings/$L4" "" "$TOKEN_A"
expect 204 "clean up"

# ---------------------------------------------------------------------------
section "scan (S-10)"
# scan TOKEN [curl -F args...] -> POST /scan multipart; sets STATUS and SCAN_SECS, body in $BODY
scan() {
  local token="$1"; shift
  local args=(-sS -o "$BODY" -w '%{http_code} %{time_total}' -X POST --max-time 40)
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  local out
  out="$(curl "${args[@]}" "$@" "$BASE_URL/scan")" || out="curl-error 0"
  STATUS="${out%% *}"; SCAN_SECS="${out#* }"
}

scan "$TOKEN_A" -F "photos=@$SMALL_JPEG;type=image/jpeg" -F "photos=@$SMALL_JPEG;type=image/jpeg" \
  -F "kinds=front, LABEL" -F "labels=t-shirt, red, cotton"
expect 200 "POST /scan with 2 photos and labels (${SCAN_SECS}s)"
check 'sorted(d) == ["draft", "photos", "source"]' "scan body has photos, draft, source"
check 'd["source"] in ("vision", "labels", "none")' "source is vision|labels|none ($(jget 'd["source"]'))"
check 'sorted(d["draft"]) == sorted(["title","category","size","color","brand","condition","condition_note","description","tags"])' "draft has exactly the ScanDraft keys"
check 'd["draft"]["condition_note"] is None or (isinstance(d["draft"]["condition_note"], str) and 0 < len(d["draft"]["condition_note"]) <= 140 and not d["draft"]["condition_note"].endswith("."))' "draft condition_note is null or a short phrase (S-28)"
check 'd["source"] == "vision" or d["draft"]["condition_note"] is None' "condition_note only comes from the vision path"
check 'isinstance(d["draft"]["tags"], list) and all(isinstance(t, str) and t == t.lower() for t in d["draft"]["tags"])' "draft tags is a list of lowercase strings"
check 'd["draft"]["category"] in (None, "tops", "bottoms", "outerwear", "dresses", "shoes", "accessories", "bags")' "draft category is an enum value or null"
check 'd["draft"]["condition"] in (None, "new", "like_new", "good", "worn")' "draft condition is an enum value or null"
check 'all(v is None or isinstance(v, str) for k, v in d["draft"].items() if k != "tags")' "draft text fields are strings or null"
check 'd["source"] != "none" or (d["draft"]["tags"] == [] and all(v is None for k, v in d["draft"].items() if k != "tags"))' "source none means an all-null draft"
check "[p['kind'] for p in d['photos']] == ['front', 'label'] and all(p['url'].startswith('$BASE_URL/media/') for p in d['photos'])" "scan returns the saved photos in order"
SCAN_P1="$(jget 'd["photos"][0]["id"]')"; SCAN_P2="$(jget 'd["photos"][1]["id"]')"
fetch "$(jget 'd["photos"][0]["url"]')" "$TMP/scan.jpg"
[[ "$STATUS" == "200" && "$CTYPE" == image/jpeg* ]] || fail "scanned photo URL loads"
ok "scanned photo URL loads"
req POST /listings "{\"title\": \"Smoke scanned tee $RUN\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$SCAN_P1, $SCAN_P2]}" "$TOKEN_A"
expect 201 "scanned photos post as a listing"
check "[p['id'] for p in d['photos']] == [$SCAN_P1, $SCAN_P2]" "listing keeps the scan's photo order"
req DELETE "/listings/$(jget 'd["id"]')" "" "$TOKEN_A"
expect 204 "clean up"

scan "" -F "photos=@$SMALL_JPEG;type=image/jpeg" -F "kinds=front"
expect 401 unauthorized "POST /scan without a token"
scan "$TOKEN_A" -F "kinds=front"
expect 400 bad_request "POST /scan with no photos"
scan "$TOKEN_A" -F "photos=@$SMALL_JPEG" -F "photos=@$SMALL_JPEG" -F "photos=@$SMALL_JPEG" -F "photos=@$SMALL_JPEG" -F "kinds=front,back,label,other"
expect 400 too_many_photos "POST /scan with 4 photos"
scan "$TOKEN_A" -F "photos=@$SMALL_JPEG" -F "photos=@$SMALL_JPEG" -F "kinds=front"
expect 400 bad_request "POST /scan with kinds that don't match the photos"
scan "$TOKEN_A" -F "photos=@$SMALL_JPEG"
expect 400 bad_request "POST /scan without kinds"
scan "$TOKEN_A" -F "photos=@$SMALL_JPEG" -F "kinds=sideways"
expect 400 bad_request "POST /scan with an unknown kind"
scan "$TOKEN_A" -F "photos=@$SMALL_JPEG" -F "photos=@$FAKE_JPEG" -F "kinds=front,back"
expect 400 bad_request "POST /scan with a broken JPEG"
scan "$TOKEN_A" -F "photos=@$HUGE;type=image/jpeg" -F "kinds=front"
expect 400 photo_too_large "POST /scan with a photo over 5 MB"

# ---------------------------------------------------------------------------
section "requests (S-12)"
# A owns L1 (swap jacket) and L2 (tee); B and D are on A's campus, C on another.
req POST /auth/login "{\"email\": \"smoke.d${RUN}@smoke.edu\"}"
expect 200 "login user D on A's campus"
TOKEN_D="$(jget 'd["token"]')"
USER_D="$(jget 'd["user"]["id"]')"
req GET /me "" "$TOKEN_B"
USER_B="$(jget 'd["id"]')"

REQ_KEYS='{"id","listing","requester","owner","note","status","unread_messages","created_at","updated_at"}'

req POST "/listings/$L1/requests" '{"note": "  Would you swap for a fleece in size M?  "}' "$TOKEN_B"
expect 201 "B requests L1 with a note"
check "set(d) == $REQ_KEYS" "Request has exactly the contract keys"
check "d['note'] == 'Would you swap for a fleece in size M?' and d['status'] == 'pending' and d['unread_messages'] == 0" "note trimmed, pending, no unread"
check "set(d['listing']) == {'id','title','photo_url','share_type','status'} and d['listing']['id'] == $L1 and d['listing']['title'] == 'Smoke trucker jacket edited $MK'" "listing summary"
check "d['listing']['photo_url'].startswith('$BASE_URL/media/') and d['listing']['share_type'] == 'swap' and d['listing']['status'] == 'active'" "summary photo_url, share_type, status"
check "set(d['requester']) == {'id','name','dorm','avatar_url','items_shared'} and d['requester']['id'] == $USER_B" "requester is B as an Owner"
check "d['owner'] == {'id': $USER_A, 'name': 'Smoke Tester', 'dorm': None, 'avatar_url': '$AVATAR_URL', 'items_shared': 0}" "owner is A as an Owner"
check "ISO.match(d['created_at']) and ISO.match(d['updated_at'])" "timestamps ISO Z"
RB="$(jget 'd["id"]')"

req POST "/listings/$L1/requests" '{}' "$TOKEN_B"
expect 409 already_requested "B requests L1 twice"
req POST "/listings/$L1/requests" '{}' "$TOKEN_A"
expect 409 own_listing "A requests own listing"
req POST "/listings/$L1/requests" '{}' "$TOKEN_C"
expect 404 not_found "request from another campus is 404"
req POST "/listings/999999999/requests" '{}' "$TOKEN_B"
expect 404 not_found "request a listing that doesn't exist"
req POST "/listings/$L1/requests" '{}'
expect 401 unauthorized "request without a token"
req POST "/listings/$L2/requests" "{\"note\": \"$(printf 'n%.0s' {1..281})\"}" "$TOKEN_B"
expect 400 bad_request "note over 280"
req POST "/listings/$L2/requests" '{"note": 5}' "$TOKEN_B"
expect 400 bad_request "note not a string"

req POST "/listings/$L1/requests" '{}' "$TOKEN_D"
expect 201 "D requests L1 with {}"
check "d['note'] is None and d['requester']['id'] == $USER_D" "note null"
RD="$(jget 'd["id"]')"
req POST "/listings/$L2/requests" "" "$TOKEN_D"
expect 201 "D requests L2 with no body"
RD2="$(jget 'd["id"]')"

req GET "/listings/$L1" "" "$TOKEN_B"
check "d['my_request_status'] == 'pending' and d['my_request_id'] == $RB and d['pending_request_count'] == 0 and d['accepted_request_id'] is None" "B's listing view: my_request pending"
req GET "/listings/$L1" "" "$TOKEN_A"
check "d['pending_request_count'] == 2 and d['accepted_request_id'] is None and d['my_request_id'] is None" "A's listing view: 2 pending requests"
req GET /me/unread "" "$TOKEN_A"
check "d['incoming_requests'] == 3" "A's unread incoming_requests is 3"
req GET /me/unread "" "$TOKEN_B"
check "d['incoming_requests'] == 0" "B has no incoming requests"

# Lists
req GET "/me/requests?role=incoming" "" "$TOKEN_A"
expect 200 "GET /me/requests?role=incoming"
check "set(d) == {'items','total','next_offset'} and d['total'] == 3 and d['next_offset'] is None" "paged, 3 incoming"
check "[x['id'] for x in d['items']] == [$RD2, $RD, $RB]" "most recently updated first"
check "all(set(x) == $REQ_KEYS for x in d['items'])" "incoming items are full Requests"
req GET "/me/requests?role=incoming&limit=1" "" "$TOKEN_A"
check "len(d['items']) == 1 and d['total'] == 3 and d['next_offset'] == 1" "incoming paged"
req GET "/me/requests?role=outgoing" "" "$TOKEN_D"
check "[x['id'] for x in d['items']] == [$RD2, $RD]" "D's outgoing"
req GET "/me/requests?role=outgoing" "" "$TOKEN_A"
check "d == {'items': [], 'total': 0, 'next_offset': None}" "A has no outgoing"
req GET /me/requests "" "$TOKEN_A"
expect 400 bad_request "role is required"
req GET "/me/requests?role=sent" "" "$TOKEN_A"
expect 400 bad_request "unknown role"

# One request
req GET "/requests/$RB" "" "$TOKEN_B"
expect 200 "requester GETs the request"
check "d['id'] == $RB and set(d) == $REQ_KEYS" "same Request shape"
req GET "/requests/$RB" "" "$TOKEN_A"
expect 200 "owner GETs the request"
req GET "/requests/$RB" "" "$TOKEN_D"
expect 403 forbidden "someone else on the campus can't see it"
req GET "/requests/$RB" "" "$TOKEN_C"
expect 404 not_found "another campus gets 404"
req GET "/requests/999999999" "" "$TOKEN_A"
expect 404 not_found "request that doesn't exist"

# Permissions and wrong states before accept
req POST "/requests/$RB/accept" "" "$TOKEN_B"
expect 403 forbidden "requester can't accept"
req POST "/requests/$RB/decline" "" "$TOKEN_B"
expect 403 forbidden "requester can't decline"
req POST "/requests/$RB/cancel" "" "$TOKEN_A"
expect 403 forbidden "owner can't cancel"
req POST "/requests/$RB/complete" "" "$TOKEN_D"
expect 403 forbidden "outsider can't complete"
req POST "/requests/$RB/accept" "" "$TOKEN_C"
expect 404 not_found "another campus can't accept"
req POST "/requests/$RB/complete" "" "$TOKEN_A"
expect 409 wrong_status "can't complete a pending request"

# Accept B: D's pending request on L1 is declined, L1 goes pending
req POST "/requests/$RB/accept" "" "$TOKEN_A"
expect 200 "A accepts B's request"
check "d['status'] == 'accepted' and d['listing']['status'] == 'pending'" "accepted, listing pending"
RB_ACCEPTED_AT="$(jget 'd["updated_at"]')"
req GET "/requests/$RD" "" "$TOKEN_D"
check "d['status'] == 'declined' and d['listing']['status'] == 'pending'" "D's other request auto-declined"
req GET "/requests/$RD2" "" "$TOKEN_D"
check "d['status'] == 'pending'" "D's request on another listing untouched"
req POST "/requests/$RB/accept" "" "$TOKEN_A"
expect 409 wrong_status "accept twice"
req POST "/requests/$RB/decline" "" "$TOKEN_A"
expect 409 wrong_status "decline an accepted request"
req POST "/requests/$RD/accept" "" "$TOKEN_A"
expect 409 wrong_status "accept a declined request"
req POST "/requests/$RD/cancel" "" "$TOKEN_D"
expect 409 wrong_status "cancel a declined request"
req POST "/listings/$L1/requests" '{}' "$TOKEN_D"
expect 409 listing_unavailable "D re-requests a pending listing"
req POST "/listings/$L1/requests" '{}' "$TOKEN_B"
expect 409 already_requested "B re-requests while accepted"

req GET "/listings?q=$MK" "" "$TOKEN_B"
check "$L1 not in [x['id'] for x in d['items']]" "pending listing drops out of the feed"
req GET /me/listings "" "$TOKEN_A"
check "[(x['status'], x['accepted_request_id'], x['pending_request_count']) for x in d['items'] if x['id'] == $L1] == [('pending', $RB, 0)]" "A's My listings: L1 pending with accepted_request_id"
req GET "/listings/$L1" "" "$TOKEN_B"
expect 200 "B GETs the pending listing"
check "d['status'] == 'pending' and d['my_request_status'] == 'accepted' and d['my_request_id'] == $RB and d['accepted_request_id'] is None" "B's view: my_request accepted, owner fields hidden"
req GET "/listings/$L1" "" "$TOKEN_D"
check "d['my_request_status'] == 'declined' and d['my_request_id'] == $RD" "D's view: my_request declined"
req GET /me/unread "" "$TOKEN_A"
check "d['incoming_requests'] == 1" "A's incoming_requests is 1 after accept"

# Cancel paths on L2: accept D, then D cancels -> L2 back to active
req POST "/listings/$L2/requests" '{"note": "me too"}' "$TOKEN_B"
expect 201 "B requests L2"
RB2="$(jget 'd["id"]')"
req POST "/requests/$RD2/accept" "" "$TOKEN_A"
expect 200 "A accepts D's request on L2"
req GET "/requests/$RB2" "" "$TOKEN_B"
check "d['status'] == 'declined'" "B's L2 request auto-declined"
req POST "/requests/$RD2/cancel" "" "$TOKEN_D"
expect 200 "D cancels an accepted request"
check "d['status'] == 'cancelled' and d['listing']['status'] == 'active'" "cancelled, listing back to active"
req GET "/listings?q=$MK" "" "$TOKEN_B"
check "$L2 in [x['id'] for x in d['items']]" "L2 is back in the feed"
req POST "/requests/$RD2/cancel" "" "$TOKEN_D"
expect 409 wrong_status "cancel twice"
req POST "/requests/$RD2/complete" "" "$TOKEN_D"
expect 409 wrong_status "complete a cancelled request"
req POST "/listings/$L2/requests" '{}' "$TOKEN_B"
expect 201 "B requests again after a decline"
RB3="$(jget 'd["id"]')"
req GET "/listings/$L2" "" "$TOKEN_B"
check "d['my_request_status'] == 'pending' and d['my_request_id'] == $RB3" "my_request is the latest request"
req POST "/requests/$RB3/decline" "" "$TOKEN_A"
expect 200 "A declines B"
check "d['status'] == 'declined' and d['listing']['status'] == 'active'" "declined, listing still active"
req POST "/listings/$L2/requests" '{}' "$TOKEN_D"
expect 201 "D requests again after cancelling"
RD3="$(jget 'd["id"]')"
req POST "/requests/$RD3/cancel" "" "$TOKEN_D"
expect 200 "D cancels a pending request"
check "d['status'] == 'cancelled'" "pending request cancelled"
req GET "/listings/$L2" "" "$TOKEN_A"
check "d['status'] == 'active' and d['pending_request_count'] == 0 and d['accepted_request_id'] is None" "L2 active, nothing open"

# Complete L1 (either side may)
sleep 1  # timestamps are whole seconds; make sure complete lands in a later second than accept
req POST "/requests/$RB/complete" "" "$TOKEN_B"
expect 200 "B (requester) completes the exchange"
check "d['status'] == 'completed' and d['listing']['status'] == 'completed' and d['owner']['items_shared'] == 1" "completed, listing completed, owner items_shared 1"
check "d['updated_at'] > '$RB_ACCEPTED_AT'" "complete bumps updated_at"
RB_DONE_AT="$(jget 'd["updated_at"]')"
req POST "/requests/$RB/complete" "" "$TOKEN_A"
expect 409 wrong_status "complete twice"
req POST "/requests/$RB/cancel" "" "$TOKEN_B"
expect 409 wrong_status "cancel a completed request"
req GET /me "" "$TOKEN_A"
check "d['items_shared'] == 1" "A's items_shared is 1"
req GET "/me/listings?status=completed" "" "$TOKEN_A"
check "[x['id'] for x in d['items']] == [$L1] and d['items'][0]['status'] == 'completed'" "L1 in A's completed listings"
req GET /me/listings "" "$TOKEN_A"
check "$L1 not in [x['id'] for x in d['items']]" "L1 not in A's active listings"
req GET "/listings/$L1" "" "$TOKEN_D"
expect 200 "completed listing still loads"
check "d['status'] == 'completed' and d['owner']['items_shared'] == 1" "listing completed, owner items_shared 1"
req POST "/listings/$L1/requests" '{}' "$TOKEN_D"
expect 409 listing_unavailable "request a completed listing"
req PATCH "/listings/$L1" '{"title": "x"}' "$TOKEN_A"
expect 409 wrong_status "PATCH a completed listing"
req DELETE "/listings/$L1" "" "$TOKEN_A"
expect 409 wrong_status "DELETE a completed listing"
req GET "/me/requests?role=incoming" "" "$TOKEN_A"
check "d['total'] == 6 and [x['updated_at'] for x in d['items'] if x['id'] == $RB] == ['$RB_DONE_AT'] == [d['items'][0]['updated_at']]" "6 incoming, the completed one has the newest updated_at"
# Timestamps are whole seconds, so several requests can tie; ties go newest id first.
check "[x['id'] for x in d['items']] == [x['id'] for x in sorted(d['items'], key=lambda x: (x['updated_at'], x['id']), reverse=True)]" "sorted by updated_at desc, then id desc"
req GET /me/unread "" "$TOKEN_A"
check "d['incoming_requests'] == 0" "no pending incoming requests left"

# Deleting a listing removes its requests
req DELETE "/listings/$L2" "" "$TOKEN_A"
expect 204 "A deletes L2"
req GET "/requests/$RD2" "" "$TOKEN_D"
expect 404 not_found "its requests are gone"
req GET "/me/requests?role=outgoing" "" "$TOKEN_D"
check "[x['id'] for x in d['items']] == [$RD]" "D's outgoing only has the L1 request"

# ---------------------------------------------------------------------------
section "messages (S-13)"
# A owns L5, B's request RM on it gets accepted, and A and B chat. D (same campus)
# and C (other campus) are outsiders. Message IDs are compared by id, never by time.
MSG_KEYS='{"id","request_id","sender_id","body","created_at"}'
upload "$SMALL_JPEG" front "$TOKEN_A"
expect 201 "upload a photo for the chat listing"
P_MSG="$(jget 'd["id"]')"
req POST /listings "{\"title\": \"Smoke chat hoodie $MK\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P_MSG]}" "$TOKEN_A"
expect 201 "A lists L5"
L5="$(jget 'd["id"]')"
req POST "/listings/$L5/requests" '{}' "$TOKEN_B"
expect 201 "B requests L5"
RM="$(jget 'd["id"]')"

# Pending: readable, not sendable
req GET "/requests/$RM/messages" "" "$TOKEN_B"
expect 200 "GET messages on a pending request"
check "d == {'items': []}" "no messages yet"
req POST "/requests/$RM/messages" '{"body": "hi"}' "$TOKEN_B"
expect 409 wrong_status "can't chat on a pending request"
req POST "/requests/$RD/messages" '{"body": "hi"}' "$TOKEN_D"
expect 409 wrong_status "can't chat on a declined request"
req GET "/requests/$RD/messages" "" "$TOKEN_D"
expect 200 "declined request's messages still readable"
req POST "/requests/$RB/messages" '{"body": "hi"}' "$TOKEN_B"
expect 409 wrong_status "can't chat on a completed request"

req POST "/requests/$RM/accept" "" "$TOKEN_A"
expect 200 "A accepts RM"
RM_ACCEPTED_AT="$(jget 'd["updated_at"]')"
req GET /me/unread "" "$TOKEN_A"
A_MSG0="$(jget 'd["messages"]')"
req GET /me/unread "" "$TOKEN_B"
B_MSG0="$(jget 'd["messages"]')"

# B sends; A has one unread
sleep 1  # whole-second timestamps: make the send land after the accept
req POST "/requests/$RM/messages" '{"body": "  Commons at 4?  "}' "$TOKEN_B"
expect 201 "B sends a message"
check "set(d) == $MSG_KEYS" "Message has exactly the contract keys"
check "d['body'] == 'Commons at 4?' and d['request_id'] == $RM and d['sender_id'] == $USER_B and ISO.match(d['created_at'])" "body trimmed, request_id, sender_id, created_at"
M1="$(jget 'd["id"]')"
req GET /me/unread "" "$TOKEN_A"
check "d['messages'] == $A_MSG0 + 1" "A's unread messages +1"
req GET /me/unread "" "$TOKEN_B"
check "d['messages'] == $B_MSG0" "B's own message isn't unread for B"
req GET "/requests/$RM" "" "$TOKEN_A"
check "d['unread_messages'] == 1" "A sees unread_messages 1 on the Request"
check "d['updated_at'] > '$RM_ACCEPTED_AT'" "sending bumps the Request's updated_at"
req GET "/requests/$RM" "" "$TOKEN_B"
check "d['unread_messages'] == 0" "B sees unread_messages 0"
req GET "/me/requests?role=incoming" "" "$TOKEN_A"
check "d['items'][0]['id'] == $RM and d['items'][0]['unread_messages'] == 1" "chat moves RM to the top of A's inbox, with its unread count"

req POST "/requests/$RM/messages" '{"body": "Or Rand tomorrow"}' "$TOKEN_B"
expect 201 "B sends a second message"
M2="$(jget 'd["id"]')"
[[ "$M2" -gt "$M1" ]] || fail "message ids increase"
req GET "/requests/$RM" "" "$TOKEN_A"
check "d['unread_messages'] == 2" "A has 2 unread"
RM_SENT_AT="$(jget 'd["updated_at"]')"

# A reads everything; reading clears unread and doesn't touch updated_at
sleep 1
req GET "/requests/$RM/messages" "" "$TOKEN_A"
expect 200 "A GETs all messages"
check "[m['id'] for m in d['items']] == [$M1, $M2] and all(set(m) == $MSG_KEYS for m in d['items'])" "oldest first, full Messages"
check "[m['body'] for m in d['items']] == ['Commons at 4?', 'Or Rand tomorrow']" "bodies in order"
req GET "/requests/$RM" "" "$TOKEN_A"
check "d['unread_messages'] == 0" "reading clears A's unread_messages"
check "d['updated_at'] == '$RM_SENT_AT'" "reading doesn't change updated_at"
req GET /me/unread "" "$TOKEN_A"
check "d['messages'] == $A_MSG0" "A's /me/unread messages back to before"

# A replies; B polls with after_id
req POST "/requests/$RM/messages" '{"body": "Works for me, see you there."}' "$TOKEN_A"
expect 201 "A replies"
check "d['sender_id'] == $USER_A" "sender is A"
M3="$(jget 'd["id"]')"
req GET /me/unread "" "$TOKEN_B"
check "d['messages'] == $B_MSG0 + 1" "B's unread messages +1"
req GET "/me/requests?role=outgoing" "" "$TOKEN_B"
check "[x['unread_messages'] for x in d['items'] if x['id'] == $RM] == [1]" "B's outgoing list shows 1 unread on RM"
req GET "/requests/$RM/messages?after_id=$M2" "" "$TOKEN_B"
expect 200 "B polls after_id=M2"
check "[m['id'] for m in d['items']] == [$M3] and d['items'][0]['body'] == 'Works for me, see you there.'" "only the newer message"
req GET "/requests/$RM" "" "$TOKEN_B"
check "d['unread_messages'] == 0" "polling clears B's unread"
req GET "/requests/$RM/messages?after_id=$M3" "" "$TOKEN_B"
check "d == {'items': []}" "poll with the newest id returns nothing"
req GET "/requests/$RM/messages?after_id=$M1" "" "$TOKEN_B"
check "[m['id'] for m in d['items']] == [$M2, $M3]" "after_id=M1 returns the two after it"
req GET /me/unread "" "$TOKEN_B"
check "d['messages'] == $B_MSG0" "B's /me/unread messages back to before"

# Body validation
LONG_1000="$(printf 'm%.0s' {1..1000})"
req POST "/requests/$RM/messages" "{\"body\": \"$LONG_1000\"}" "$TOKEN_A"
expect 201 "1000-character message"
check "len(d['body']) == 1000" "full body kept"
req POST "/requests/$RM/messages" "{\"body\": \"${LONG_1000}m\"}" "$TOKEN_A"
expect 400 bad_request "1001 characters"
req POST "/requests/$RM/messages" '{"body": "   "}' "$TOKEN_A"
expect 400 bad_request "blank body"
req POST "/requests/$RM/messages" '{}' "$TOKEN_A"
expect 400 bad_request "missing body"
req POST "/requests/$RM/messages" "" "$TOKEN_A"
expect 400 bad_request "no JSON at all"
req POST "/requests/$RM/messages" '{"body": 5}' "$TOKEN_A"
expect 400 bad_request "body not a string"
req GET "/requests/$RM/messages?after_id=abc" "" "$TOKEN_A"
expect 400 bad_request "after_id not a number"
req GET "/requests/$RM" "" "$TOKEN_B"
check "d['unread_messages'] == 1" "only the valid long message counts for B"

# Outsiders
req GET "/requests/$RM/messages" "" "$TOKEN_D"
expect 403 forbidden "D on the campus can't read"
req POST "/requests/$RM/messages" '{"body": "hi"}' "$TOKEN_D"
expect 403 forbidden "D can't send"
req GET "/requests/$RM/messages" "" "$TOKEN_C"
expect 404 not_found "another campus can't read"
req POST "/requests/$RM/messages" '{"body": "hi"}' "$TOKEN_C"
expect 404 not_found "another campus can't send"
req GET "/requests/999999999/messages" "" "$TOKEN_A"
expect 404 not_found "messages on a request that doesn't exist"
req GET "/requests/$RM/messages"
expect 401 unauthorized "read without a token"
req POST "/requests/$RM/messages" '{"body": "hi"}'
expect 401 unauthorized "send without a token"

# After completion: readable, closed for sending
req POST "/requests/$RM/complete" "" "$TOKEN_A"
expect 200 "A completes RM"
req POST "/requests/$RM/messages" '{"body": "thanks!"}' "$TOKEN_B"
expect 409 wrong_status "can't chat after completion"
req GET "/requests/$RM/messages" "" "$TOKEN_B"
expect 200 "completed chat still readable"
check "len(d['items']) == 4 and [m['id'] for m in d['items']] == sorted(m['id'] for m in d['items'])" "all 4 messages, ascending ids"
req GET "/requests/$RM" "" "$TOKEN_B"
check "d['unread_messages'] == 0" "B read the long message"

# ---------------------------------------------------------------------------
section "impact (S-17)"
# A shared L1 (outerwear) and L5 (tops), both received by B. D has none yet.
# smoke.edu campus totals accumulate across runs, so campus checks compare before/after.
ME_IMPACT_KEYS="{'items_shared','items_received','textile_kg','water_l','co2_kg'}"
CAMPUS_IMPACT_KEYS="{'items_rehomed','textile_kg','water_l','co2_kg','top_dorm'}"
NUMS="all(isinstance(d[k], (int, float)) and not isinstance(d[k], bool) and d[k] >= 0 for k in ('textile_kg','water_l','co2_kg'))"
req GET "/listings/$L1" "" "$TOKEN_A"
IMP_L1="$(jget "repr(d['impact'])")"
req GET "/listings/$L5" "" "$TOKEN_A"
IMP_L5="$(jget "repr(d['impact'])")"
# Expected totals: sum of the two items, allowing for rounding of each item vs the total.
SUM_OK="all(abs(d[k] - ($IMP_L1[k] + $IMP_L5[k])) <= tol for k, tol in (('textile_kg', 0.02), ('water_l', 2), ('co2_kg', 0.2)))"

req GET /impact/me "" "$TOKEN_A"
expect 200 "GET /impact/me (owner A)"
check "set(d) == $ME_IMPACT_KEYS and $NUMS" "impact/me has exactly the contract keys, numbers"
check "d['items_shared'] == 2 and d['items_received'] == 0" "A shared 2, received 0"
check "$SUM_OK" "A's totals add up L1 + L5"
check "d['co2_kg'] > 10 and d['water_l'] > 1000" "A's totals are non-trivial"
req GET /impact/me "" "$TOKEN_B"
expect 200 "GET /impact/me (requester B)"
check "d['items_shared'] == 0 and d['items_received'] == 2 and $SUM_OK" "B received 2, same totals (both sides get credit)"
req GET /impact/me "" "$TOKEN_D"
check "d == {'items_shared': 0, 'items_received': 0, 'textile_kg': 0, 'water_l': 0, 'co2_kg': 0}" "D has no impact yet"
req GET /impact/me
expect 401 unauthorized "impact/me without a token"

req GET /impact/campus "" "$TOKEN_D"
expect 200 "GET /impact/campus"
check "set(d) == $CAMPUS_IMPACT_KEYS and $NUMS and isinstance(d['items_rehomed'], int)" "impact/campus has exactly the contract keys"
check "d['items_rehomed'] >= 2 and d['co2_kg'] > 0 and (d['top_dorm'] is None or isinstance(d['top_dorm'], str))" "campus counts this run's 2 exchanges"
CAMPUS_BEFORE="$(jget "repr(d)")"
req GET /impact/campus "" "$TOKEN_C"
expect 200 "impact/campus on another campus"
check "set(d) == $CAMPUS_IMPACT_KEYS" "other campus: same shape"
req GET /impact/campus
expect 401 unauthorized "impact/campus without a token"

# A new exchange on smoke.edu: D gives away a dress to B.
upload "$SMALL_JPEG" front "$TOKEN_D"
expect 201 "upload a photo for the impact listing"
P_IMP="$(jget 'd["id"]')"
req POST /listings "{\"title\": \"Smoke impact dress $MK\", \"category\": \"dresses\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P_IMP]}" "$TOKEN_D"
expect 201 "D lists a dress"
L_IMP="$(jget 'd["id"]')"
IMP_DRESS="$(jget "repr(d['impact'])")"
req POST "/listings/$L_IMP/requests" '{}' "$TOKEN_B"
expect 201 "B requests the dress"
R_IMP="$(jget 'd["id"]')"
req GET /impact/campus "" "$TOKEN_D"
check "d == $CAMPUS_BEFORE" "a pending request adds nothing"
req POST "/requests/$R_IMP/accept" "" "$TOKEN_D"
expect 200 "D accepts"
req GET /impact/me "" "$TOKEN_D"
check "d['items_shared'] == 0 and d['co2_kg'] == 0" "an accepted request adds nothing"
req POST "/requests/$R_IMP/complete" "" "$TOKEN_D"
expect 200 "D completes the dress exchange"
req GET /impact/me "" "$TOKEN_D"
check "d == {'items_shared': 1, 'items_received': 0, **$IMP_DRESS}" "D's impact is exactly the dress's impact"
req GET /impact/me "" "$TOKEN_B"
check "d['items_received'] == 3 and d['co2_kg'] > ($IMP_L1['co2_kg'] + $IMP_L5['co2_kg'])" "B's totals went up"
req GET /impact/campus "" "$TOKEN_A"
check "d['items_rehomed'] >= $CAMPUS_BEFORE['items_rehomed'] + 1 and d['co2_kg'] > $CAMPUS_BEFORE['co2_kg'] and d['water_l'] > $CAMPUS_BEFORE['water_l'] and d['textile_kg'] > $CAMPUS_BEFORE['textile_kg']" "campus totals increased after the exchange"

section "saves (S-18)"
# Fresh user E saves A's listings. L1 is A's completed jacket (saved lists keep any status
# but hidden). C is on another campus.
req POST /auth/login "{\"email\": \"smoke.e${RUN}@smoke.edu\"}"
expect 200 "login user E on A's campus"
TOKEN_E="$(jget 'd["token"]')"
req GET /me/saved "" "$TOKEN_E"
expect 200 "GET /me/saved (empty)"
check "d == {'items': [], 'total': 0, 'next_offset': None}" "new user has no saves"

SV=()
for n in 1 2 3; do
  P_SV="$(up "$SMALL_JPEG" front "$TOKEN_A")" || exit 1
  req POST /listings "{\"title\": \"Smoke save $n $MK\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"free\", \"tags\": [\"savetag${RUN}\"], \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P_SV]}" "$TOKEN_A"
  [[ "$STATUS" == 201 ]] || fail "A lists save item $n"
  SV+=("$(jget 'd["id"]')")
done
ok "A listed 3 items to save"
SV1="${SV[0]}"; SV2="${SV[1]}"; SV3="${SV[2]}"

req PUT "/listings/$SV1/save" "" "$TOKEN_E"
expect 204 "PUT /listings/{id}/save"
[[ ! -s "$BODY" ]] || fail "PUT save has an empty body"
ok "PUT save body is empty"
req PUT "/listings/$SV1/save" "" "$TOKEN_E"
expect 204 "PUT save again is still 204"
req GET "/listings/$SV1" "" "$TOKEN_E"
check "d['saved_by_me'] is True" "detail: saved_by_me true for the saver"
req GET "/listings/$SV1" "" "$TOKEN_A"
check "d['saved_by_me'] is False" "detail: saved_by_me false for someone else"
req GET "/listings?q=savetag${RUN}" "" "$TOKEN_E"
expect 200 "feed with the save tag"
check "d['total'] == 3 and {l['id']: l['saved_by_me'] for l in d['items']} == {$SV1: True, $SV2: False, $SV3: False}" "feed: saved_by_me true only on the saved one"

sleep 1  # whole-second save times: each save lands in a later second
req PUT "/listings/$L1/save" "" "$TOKEN_E"
expect 204 "save a completed listing"
sleep 1
req PUT "/listings/$SV2/save" "" "$TOKEN_E"
expect 204 "save a second item"
sleep 1
req PUT "/listings/$SV3/save" "" "$TOKEN_E"
expect 204 "save a third item"
req PUT "/listings/$SV1/save" "" "$TOKEN_E"
expect 204 "re-save the first item"

req GET /me/saved "" "$TOKEN_E"
expect 200 "GET /me/saved"
check "[l['id'] for l in d['items']] == [$SV3, $SV2, $L1, $SV1] and d['total'] == 4 and d['next_offset'] is None" "newest save first; re-saving keeps the original time"
check "all(set(l) == $LISTING_KEYS for l in d['items'])" "saved items are full Listings"
check "all(l['saved_by_me'] is True and l['is_mine'] is False for l in d['items'])" "every saved item has saved_by_me true"
check "next(l for l in d['items'] if l['id'] == $L1)['status'] == 'completed'" "a completed listing stays in the saved list with its status"
req GET "/me/saved?limit=2" "" "$TOKEN_E"
expect 200 "GET /me/saved page 1"
check "[l['id'] for l in d['items']] == [$SV3, $SV2] and d['total'] == 4 and d['next_offset'] == 2" "page 1 of 2"
req GET "/me/saved?limit=2&offset=2" "" "$TOKEN_E"
expect 200 "GET /me/saved page 2"
check "[l['id'] for l in d['items']] == [$L1, $SV1] and d['total'] == 4 and d['next_offset'] is None" "page 2 of 2, last page"
req GET "/me/saved?limit=0" "" "$TOKEN_E"
expect 400 bad_request "GET /me/saved limit=0"

req DELETE "/listings/$SV2/save" "" "$TOKEN_E"
expect 204 "DELETE /listings/{id}/save"
[[ ! -s "$BODY" ]] || fail "DELETE save has an empty body"
req DELETE "/listings/$SV2/save" "" "$TOKEN_E"
expect 204 "DELETE save again is still 204"
req DELETE "/listings/$L5/save" "" "$TOKEN_E"
expect 204 "DELETE save on a never-saved listing is 204"
req GET "/listings/$SV2" "" "$TOKEN_E"
check "d['saved_by_me'] is False" "unsaved: saved_by_me false"
req GET "/listings?q=savetag${RUN}" "" "$TOKEN_E"
check "{l['id']: l['saved_by_me'] for l in d['items']} == {$SV1: True, $SV2: False, $SV3: True}" "feed flags follow save and unsave"
req DELETE "/listings/$SV3" "" "$TOKEN_A"
expect 204 "A deletes a listing E saved"
req GET /me/saved "" "$TOKEN_E"
check "[l['id'] for l in d['items']] == [$L1, $SV1] and d['total'] == 2" "unsaved and deleted listings drop out of the saved list"
req GET /me/saved "" "$TOKEN_A"
check "d['total'] == 0" "saves are per user (A has none)"

req PUT "/listings/$SV1/save" "" "$TOKEN_A"
expect 204 "saving your own listing is allowed"
req GET "/listings/$SV1" "" "$TOKEN_A"
check "d['saved_by_me'] is True and d['is_mine'] is True" "own listing: saved_by_me true"
req DELETE "/listings/$SV1/save" "" "$TOKEN_A"
expect 204 "unsave your own listing"

req PUT "/listings/$SV1/save" "" "$TOKEN_C"
expect 404 not_found "PUT save on another campus's listing"
req DELETE "/listings/$SV1/save" "" "$TOKEN_C"
expect 404 not_found "DELETE save on another campus's listing"
req PUT "/listings/$SV3/save" "" "$TOKEN_E"
expect 404 not_found "PUT save on a deleted listing"
req PUT "/listings/999999999/save" "" "$TOKEN_E"
expect 404 not_found "PUT save on a missing listing"
req GET /me/saved "" "$TOKEN_C"
check "d['total'] == 0" "other-campus user's saved list is untouched"
req PUT "/listings/$SV1/save"
expect 401 unauthorized "PUT save without a token"
req DELETE "/listings/$SV1/save"
expect 401 unauthorized "DELETE save without a token"
req GET /me/saved
expect 401 unauthorized "GET /me/saved without a token"

# ---------------------------------------------------------------------------
section "similar items (S-19)"
# Score = shared tags (case-insensitive) x3 + same category x2 + same size x1; ties newest
# first. Tags and size are unique to this run, so old smoke listings can only match on
# category (score 2), and this run's listings are newer than theirs.
req POST /auth/login "{\"email\": \"smoke.f${RUN}@smoke.edu\"}"
expect 200 "login user F on A's campus"
TOKEN_F="$(jget 'd["token"]')"
T1="sima${RUN}"; T2="simb${RUN}"; T3="simc${RUN}"; SZ="q${RUN}"

# sim_list TOKEN TITLE CATEGORY SIZE TAGS_JSON -> prints the new listing's id
sim_list() {
  local pid size_json="null"
  pid="$(up "$SMALL_JPEG" front "$1")" || return 1
  [[ -n "$4" ]] && size_json="\"$4\""
  req POST /listings "{\"title\": \"Smoke similar $2 $MK\", \"category\": \"$3\", \"size\": $size_json, \"condition\": \"good\", \"share_type\": \"free\", \"tags\": $5, \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$pid]}" "$1"
  [[ "$STATUS" == 201 ]] || fail "list similar item $2"
  jget 'd["id"]'
}
SRC="$(sim_list "$TOKEN_A" source bags "$SZ" "[\"$T1\", \"$T2\", \"$T3\"]")" || exit 1
X1="$(sim_list "$TOKEN_A" x1 bags "$SZ" "[\"SIMA${RUN}\", \" $T2 \", \"$T3\"]")" || exit 1   # 9+2+1 = 12
X2="$(sim_list "$TOKEN_A" x2 tops "$SZ" "[\"$T1\", \"$T2\", \"other\"]")" || exit 1     # 6+1 = 7
X3="$(sim_list "$TOKEN_A" x3 bags "" "[\"$T2\"]")" || exit 1                              # 3+2 = 5
X4="$(sim_list "$TOKEN_A" x4 tops "$SZ" "[\"$T3\"]")" || exit 1                           # 3+1 = 4
X5="$(sim_list "$TOKEN_A" x5 tops "" "[\"$T1\"]")" || exit 1                              # 3
X6="$(sim_list "$TOKEN_A" x6 shoes "" "[\"$T2\"]")" || exit 1                             # 3, newer than X5
X7="$(sim_list "$TOKEN_A" x7 bags "" "[]")" || exit 1                                     # 2 (category only)
XOWN="$(sim_list "$TOKEN_F" own bags "$SZ" "[\"$T1\", \"$T2\", \"$T3\"]")" || exit 1      # F's own: excluded for F
XP="$(sim_list "$TOKEN_A" pend bags "$SZ" "[\"$T1\", \"$T2\", \"$T3\"]")" || exit 1       # goes pending, then completed
XD="$(sim_list "$TOKEN_A" del bags "$SZ" "[\"$T1\", \"$T2\", \"$T3\"]")" || exit 1        # deleted
PC="$(up "$SMALL_JPEG" front "$TOKEN_C")" || exit 1
req POST /listings "{\"title\": \"Smoke similar other campus $MK\", \"category\": \"bags\", \"size\": \"$SZ\", \"condition\": \"good\", \"share_type\": \"free\", \"tags\": [\"$T1\", \"$T2\", \"$T3\"], \"meetup_spot_id\": $SPOT_C, \"photo_ids\": [$PC]}" "$TOKEN_C"
[[ "$STATUS" == 201 ]] || fail "C lists a matching item on another campus"
XC="$(jget 'd["id"]')"
ok "listed source, 7 candidates, and own/pending/deleted/other-campus decoys"

req POST "/listings/$XP/requests" '{}' "$TOKEN_B"
[[ "$STATUS" == 201 ]] || fail "B requests the pending decoy"
RXP="$(jget 'd["id"]')"
req POST "/requests/$RXP/accept" "" "$TOKEN_A"
expect 200 "A accepts, decoy listing goes pending"
req DELETE "/listings/$XD" "" "$TOKEN_A"
expect 204 "A deletes the deleted decoy"
EXCL="{$SRC, $XOWN, $XP, $XD, $XC}"

req GET "/listings/$SRC/similar" "" "$TOKEN_F"
expect 200 "GET /listings/{id}/similar"
check "set(d) == {'items'}" "response is {items} only (unpaged)"
check "[l['id'] for l in d['items']] == [$X1, $X2, $X3, $X4, $X6, $X5]" "default 6, ranked by tags x3 + category x2 + size x1, ties newest first"
check "all(set(l) == $LISTING_KEYS for l in d['items'])" "similar items are full Listings"
check "all(l['status'] == 'active' and l['is_mine'] is False and l['saved_by_me'] is False for l in d['items'])" "all active, not mine, not saved"
req GET "/listings/$SRC/similar?limit=20" "" "$TOKEN_F"
expect 200 "similar limit=20"
check "[l['id'] for l in d['items']][:7] == [$X1, $X2, $X3, $X4, $X6, $X5, $X7]" "zero-tag same-category item fills in after the tag matches"
check "not ({l['id'] for l in d['items']} & $EXCL)" "never the source, F's own, pending, deleted, or other-campus listings"
check "all(l['status'] == 'active' for l in d['items']) and len(d['items']) <= 20" "only active listings, at most 20"
req GET "/listings/$SRC/similar?limit=2" "" "$TOKEN_F"
check "[l['id'] for l in d['items']] == [$X1, $X2]" "limit=2 returns the top two"
req GET "/listings/$SRC/similar?limit=500" "" "$TOKEN_F"
expect 200 "similar limit over max"
check "len(d['items']) <= 20" "limit over 20 is treated as 20"
req GET "/listings/$SRC/similar?limit=0" "" "$TOKEN_F"
expect 400 bad_request "similar limit=0"

req PUT "/listings/$X2/save" "" "$TOKEN_F"
expect 204 "F saves X2"
req GET "/listings/$SRC/similar" "" "$TOKEN_F"
check "{l['id']: l['saved_by_me'] for l in d['items']}[$X2] is True" "similar items carry saved_by_me"

req POST "/requests/$RXP/complete" "" "$TOKEN_A"
expect 200 "pending decoy completed"
req GET "/listings/$SRC/similar?limit=20" "" "$TOKEN_F"
check "$XP not in [l['id'] for l in d['items']]" "completed listing stays out"

req GET "/listings/$SRC/similar?limit=20" "" "$TOKEN_A"
expect 200 "owner asks for similar to their own listing"
check "not ({l['id'] for l in d['items']} & {$SRC, $X1, $X2, $X3, $X4, $X5, $X6, $X7}) and $XOWN in [l['id'] for l in d['items']]" "A's own listings excluded, F's listing included for A"
check "[l['id'] for l in d['items']][0] == $XOWN" "F's identical listing ranks first for A"
req GET "/listings/$XP/similar" "" "$TOKEN_F"
expect 200 "similar to a completed listing still works"
req GET "/listings/$XD/similar" "" "$TOKEN_F"
expect 404 not_found "similar to a deleted listing"
req GET "/listings/$SRC/similar" "" "$TOKEN_C"
expect 404 not_found "similar to another campus's listing"
req GET "/listings/999999999/similar" "" "$TOKEN_F"
expect 404 not_found "similar to a missing listing"
req GET "/listings/$SRC/similar"
expect 401 unauthorized "similar without a token"
# Hidden listings: no API can hide one until reports land (S-24); the route uses the same
# visibility check as GET /listings/{id} and only ranks status 'active'.

# ---------------------------------------------------------------------------
section "style it (S-20)"
# Real AI calls take ~4-7 s (occasionally over the server's 15 s limit, which returns
# template ideas, uncached). If the model is down, the "cached" check fails loudly.
STYLE_SHAPE="set(d) == {'ideas'} and 2 <= len(d['ideas']) <= 3 and all(set(i) == {'title', 'description'} and isinstance(i['title'], str) and isinstance(i['description'], str) and 0 < len(i['title']) <= 40 and 0 < len(i['description']) <= 200 for i in d['ideas'])"
PS="$(up "$SMALL_JPEG" front "$TOKEN_A")" || exit 1
req POST /listings "{\"title\": \"Smoke style denim trucker jacket $MK\", \"category\": \"outerwear\", \"size\": \"M\", \"color\": \"Light wash blue\", \"condition\": \"good\", \"share_type\": \"swap\", \"tags\": [\"denim\", \"vintage\", \"jacket\"], \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$PS]}" "$TOKEN_A"
expect 201 "A lists a denim jacket to style"
SL="$(jget 'd["id"]')"
req POST "/listings/$SL/style" "" "$TOKEN_B"
expect 200 "POST /listings/{id}/style (first call, ${SECS}s)"
check "$STYLE_SHAPE" "2-3 ideas, each a short title and description"
if ! faster_than 14; then
  # The model hit the server's 15 s limit: those were template ideas (not cached). A late
  # reply gets cached when it lands; otherwise the retry makes a fresh model call.
  echo "  ..  model timed out (template ideas); retrying in 8 s"
  sleep 8
  req POST "/listings/$SL/style" "" "$TOKEN_B"
  expect 200 "style retry after a model timeout (${SECS}s)"
  check "$STYLE_SHAPE" "retry: 2-3 well-formed ideas"
fi
cp "$BODY" "$TMP/style1.json"
req POST "/listings/$SL/style" "" "$TOKEN_A"
expect 200 "style again, as the owner"
faster_than 1 || fail "cached style call took ${SECS}s (wanted < 1 s; AI fallback not cached?)"
cmp -s "$BODY" "$TMP/style1.json" || fail "second style call returned different ideas (not cached)"
ok "second call is cached: identical ideas in ${SECS}s"
req PATCH "/listings/$SL" '{"color": "Black", "tags": ["denim", "black", "jacket"]}' "$TOKEN_A"
expect 200 "A changes the jacket's color and tags"
req POST "/listings/$SL/style" "" "$TOKEN_B"
expect 200 "style after the edit (${SECS}s)"
check "$STYLE_SHAPE" "ideas regenerated for the edited listing are well formed"
faster_than 1 && fail "style after an edit came back in ${SECS}s: stale cache served?"
faster_than 14 && how="regenerated" || how="model timed out, template ideas"
ok "edit invalidated the cache ($how in ${SECS}s)"
req POST "/listings/$SL/style" "" "$TOKEN_C"
expect 404 not_found "style another campus's listing"
req POST "/listings/$XD/style" "" "$TOKEN_A"
expect 404 not_found "style a deleted listing"
req POST "/listings/999999999/style" "" "$TOKEN_A"
expect 404 not_found "style a missing listing"
req POST "/listings/$SL/style"
expect 401 unauthorized "style without a token"

# ---------------------------------------------------------------------------
section "dorm leaderboard (S-21)"
# Fresh owners F, G, H with this run's own dorm names (smoke.edu has no dorm list, so
# dorm is free text), so their counts are exact even though smoke.edu accumulates runs.
# F's dorm completes 2 exchanges; G's and H's 1 each (a tie: same rank, alphabetical).
# I has no dorm, so I's exchange counts toward the campus but never on the board.
BOARD_OK="set(d) == {'items'} and all(set(r) == {'rank', 'dorm', 'items_shared'} and isinstance(r['dorm'], str) and r['dorm'] != '' and type(r['items_shared']) is int and r['items_shared'] > 0 and type(r['rank']) is int for r in d['items']) and len({r['dorm'] for r in d['items']}) == len(d['items']) and all(r['rank'] == 1 + sum(1 for x in d['items'] if x['items_shared'] > r['items_shared']) for r in d['items']) and [(-r['items_shared'], r['dorm'].casefold()) for r in d['items']] == sorted((-r['items_shared'], r['dorm'].casefold()) for r in d['items'])"
DORM_F="Lb North $RUN"; DORM_G="Lb South $RUN"; DORM_H="Lb East $RUN"
req GET /leaderboard/dorms "" "$TOKEN_B"
expect 200 "GET /leaderboard/dorms"
check "$BOARD_OK" "board shape: exact keys, ranks match counts, ties share a rank, ties alphabetical"
check "not {'$DORM_F', '$DORM_G', '$DORM_H'} & {r['dorm'] for r in d['items']}" "this run's dorms aren't on the board yet"
LB_BEFORE="$(jget "sum(r['items_shared'] for r in d['items'])")"

lb_user() {  # lb_user LETTER DORM_JSON -> prints a token for a fresh smoke.edu user with that dorm
  req POST /auth/login "{\"email\": \"smoke.lb$1${RUN}@smoke.edu\"}"
  [[ "$STATUS" == 200 ]] || fail "login leaderboard user $1"
  local token; token="$(jget 'd["token"]')"
  req PATCH /me "{\"dorm\": $2}" "$token"
  [[ "$STATUS" == 200 ]] || fail "set leaderboard user $1's dorm"
  echo "$token"
}
lb_exchange() {  # lb_exchange OWNER_TOKEN N -> owner lists an item, B requests it, owner accepts and completes
  local photo lid rid
  photo="$(up "$SMALL_JPEG" front "$1")" || exit 1
  req POST /listings "{\"title\": \"Smoke leaderboard tee $2 $MK\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$photo]}" "$1"
  [[ "$STATUS" == 201 ]] || fail "leaderboard listing $2"
  lid="$(jget 'd["id"]')"
  req POST "/listings/$lid/requests" '{}' "$TOKEN_B"
  [[ "$STATUS" == 201 ]] || fail "B requests leaderboard listing $2"
  rid="$(jget 'd["id"]')"
  req POST "/requests/$rid/accept" "" "$1"
  [[ "$STATUS" == 200 ]] || fail "accept leaderboard request $2"
  req POST "/requests/$rid/complete" "" "$1"
  [[ "$STATUS" == 200 ]] || fail "complete leaderboard request $2"
}
TOKEN_F="$(lb_user f "\"$DORM_F\"")" || exit 1
TOKEN_G="$(lb_user g "\"$DORM_G\"")" || exit 1
TOKEN_H="$(lb_user h "\"$DORM_H\"")" || exit 1
TOKEN_I="$(lb_user i null)" || exit 1
ok "4 owners: F, G, H in this run's dorms, I with none"

# A pending request isn't counted yet.
PLB="$(up "$SMALL_JPEG" front "$TOKEN_F")" || exit 1
req POST /listings "{\"title\": \"Smoke leaderboard pending $MK\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$PLB]}" "$TOKEN_F"
expect 201 "F lists an item"
LLB="$(jget 'd["id"]')"
req POST "/listings/$LLB/requests" '{}' "$TOKEN_B"
expect 201 "B requests it (left pending)"
req GET /leaderboard/dorms "" "$TOKEN_B"
check "'$DORM_F' not in {r['dorm'] for r in d['items']}" "a pending request doesn't put F's dorm on the board"

lb_exchange "$TOKEN_F" 1; lb_exchange "$TOKEN_F" 2
lb_exchange "$TOKEN_G" 3; lb_exchange "$TOKEN_H" 4; lb_exchange "$TOKEN_I" 5
ok "5 exchanges completed (F 2, G 1, H 1, I 1)"

req GET /leaderboard/dorms "" "$TOKEN_B"
expect 200 "leaderboard after the exchanges"
check "$BOARD_OK" "board is still consistent"
LB="{r['dorm']: r for r in d['items']}"
check "$LB['$DORM_F']['items_shared'] == 2 and $LB['$DORM_G']['items_shared'] == 1 and $LB['$DORM_H']['items_shared'] == 1" "counts by owner dorm: F 2, G 1, H 1"
check "$LB['$DORM_F']['rank'] < $LB['$DORM_H']['rank'] == $LB['$DORM_G']['rank']" "F's dorm ranks above; G and H tie on one rank"
check "[r['dorm'] for r in d['items']].index('$DORM_H') < [r['dorm'] for r in d['items']].index('$DORM_G')" "the tie is listed alphabetically (East before South)"
check "sum(r['items_shared'] for r in d['items']) == $LB_BEFORE + 4" "board total grew by 4 (I's no-dorm exchange isn't counted)"
LB_TOP="$(jget "d['items'][0]['dorm']")"
cp "$BODY" "$TMP/lb.json"
req GET /leaderboard/dorms "" "$TOKEN_F"
cmp -s "$BODY" "$TMP/lb.json" || fail "the board differs by viewer on the same campus"
ok "same board for every viewer on the campus"
req GET /impact/campus "" "$TOKEN_B"
check "d['top_dorm'] == '$LB_TOP'" "/impact/campus top_dorm is the board's first dorm"

# Counts follow the owner's current dorm: G moves to H's dorm, so H's dorm has 2 and G's is gone.
req PATCH /me "{\"dorm\": \"$DORM_H\"}" "$TOKEN_G"
expect 200 "G moves to H's dorm"
req GET /leaderboard/dorms "" "$TOKEN_B"
check "$BOARD_OK and $LB['$DORM_H']['items_shared'] == 2 and '$DORM_G' not in $LB and $LB['$DORM_H']['rank'] == $LB['$DORM_F']['rank']" "G's exchange now counts for H's dorm, tying F's"
check "[r['dorm'] for r in d['items']].index('$DORM_H') < [r['dorm'] for r in d['items']].index('$DORM_F')" "the new tie is alphabetical too (East before North)"

req GET /leaderboard/dorms "" "$TOKEN_C"
expect 200 "leaderboard on another campus"
check "$BOARD_OK and not {'$DORM_F', '$DORM_H'} & {r['dorm'] for r in d['items']}" "another campus doesn't see smoke.edu dorms"
req GET /leaderboard/dorms
expect 401 unauthorized "leaderboard without a token"

# ---------------------------------------------------------------------------
section "notifications (S-23)"
# Fresh users: owner NO (Olive), requesters N1 (Rex), N2 (Ruth), N3 (no name -> "Someone").
# Every count is exact because these users only exist for this run.
NOTIF_KEYS="{'id','type','title','body','request_id','listing_id','read','created_at'}"
nt_user() {  # nt_user LETTER [NAME] -> prints "TOKEN USER_ID" for a fresh smoke.edu user
  req POST /auth/login "{\"email\": \"smoke.nt$1${RUN}@smoke.edu\"}"
  [[ "$STATUS" == 200 ]] || fail "login notifications user $1"
  local token id; token="$(jget 'd["token"]')"; id="$(jget 'd["user"]["id"]')"
  if [[ -n "${2:-}" ]]; then
    req PATCH /me "{\"name\": \"$2\"}" "$token"
    [[ "$STATUS" == 200 ]] || fail "name notifications user $1"
  fi
  echo "$token $id"
}
nt_list() {  # nt_list TOKEN TITLE -> prints a new listing id
  local photo; photo="$(up "$SMALL_JPEG" front "$1")" || exit 1
  req POST /listings "{\"title\": \"$2\", \"category\": \"outerwear\", \"condition\": \"good\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$photo]}" "$1"
  [[ "$STATUS" == 201 ]] || fail "list $2"
  jget 'd["id"]'
}
# nts TOKEN -> GET /notifications?limit=50 into $BODY (fails the run on error)
nts() { req GET "/notifications?limit=50" "" "$1"; [[ "$STATUS" == 200 ]] || fail "GET /notifications"; }
read -r TOK_NO USR_NO <<<"$(nt_user o "Olive Smoke")" || exit 1
read -r TOK_N1 USR_N1 <<<"$(nt_user r1 "Rex Smoke")" || exit 1
read -r TOK_N2 USR_N2 <<<"$(nt_user r2 "Ruth Smoke")" || exit 1
read -r TOK_N3 USR_N3 <<<"$(nt_user r3)" || exit 1
[[ -n "$TOK_NO" && -n "$TOK_N1" && -n "$TOK_N2" && -n "$TOK_N3" && -n "$USR_N3" ]] || fail "set up notification users"
ok "4 fresh users for notifications"
NT_T1="Notif jacket $MK"; NT_T2="Notif boots $MK"
NL1="$(nt_list "$TOK_NO" "$NT_T1")" || exit 1
NL2="$(nt_list "$TOK_NO" "$NT_T2")" || exit 1
ok "owner listed 2 items"

req GET /notifications "" "$TOK_NO"
expect 200 "GET /notifications"
check "d == {'items': [], 'total': 0, 'next_offset': None, 'unread': 0}" "new user: no notifications, unread 0"
req GET /notifications
expect 401 unauthorized "GET /notifications without a token"
req POST /notifications/read '{"all": true}'
expect 401 unauthorized "POST /notifications/read without a token"

# Three requests on NL1 -> three request_received for the owner, none for the requesters.
req POST "/listings/$NL1/requests" '{}' "$TOK_N1"; [[ "$STATUS" == 201 ]] || fail "N1 requests NL1"
NR1="$(jget 'd["id"]')"
nts "$TOK_NO"
check "d['total'] == 1 and d['unread'] == 1 and set(d['items'][0]) == $NOTIF_KEYS" "owner has 1 notification with exactly the contract keys"
check "d['items'][0]['type'] == 'request_received' and d['items'][0]['title'] == 'Rex requested your item' and d['items'][0]['body'] == '$NT_T1'" "request_received: 'Rex requested your item', body is the listing title"
check "d['items'][0]['request_id'] == $NR1 and d['items'][0]['listing_id'] == $NL1 and d['items'][0]['read'] is False and ISO.match(d['items'][0]['created_at'])" "request_received IDs, unread, ISO time"
nts "$TOK_N1"
check "d['total'] == 0" "the requester isn't notified about their own request"
sleep 1
req POST "/listings/$NL1/requests" '{"note": "please!"}' "$TOK_N2"; [[ "$STATUS" == 201 ]] || fail "N2 requests NL1"
NR2="$(jget 'd["id"]')"
sleep 1
req POST "/listings/$NL1/requests" '{}' "$TOK_N3"; [[ "$STATUS" == 201 ]] || fail "N3 requests NL1"
NR3="$(jget 'd["id"]')"
nts "$TOK_NO"
check "d['total'] == 3 and d['unread'] == 3 and [n['request_id'] for n in d['items']] == [$NR3, $NR2, $NR1]" "owner has 3 unread, newest first"
check "d['items'][0]['title'] == 'Someone requested your item'" "a requester with no name shows as Someone"
req GET "/notifications?limit=2" "" "$TOK_NO"
check "len(d['items']) == 2 and d['total'] == 3 and d['next_offset'] == 2 and d['unread'] == 3" "page 1 of 2 (limit 2), unread counts every page"
req GET "/notifications?limit=2&offset=2" "" "$TOK_NO"
check "len(d['items']) == 1 and d['items'][0]['request_id'] == $NR1 and d['next_offset'] is None and d['unread'] == 3" "page 2: the oldest, last page"
req GET "/notifications?limit=0" "" "$TOK_NO"
expect 400 bad_request "limit=0 is a bad request"
req GET /me/unread "" "$TOK_NO"
check "d['notifications'] == 3 and d['incoming_requests'] == 3" "owner /me/unread: 3 notifications, 3 incoming"

# Decline N2 -> N2 gets request_declined; the owner's request_received for it is read.
req POST "/requests/$NR2/decline" "" "$TOK_NO"; [[ "$STATUS" == 200 ]] || fail "owner declines N2"
nts "$TOK_N2"
check "d['total'] == 1 and d['unread'] == 1 and d['items'][0]['type'] == 'request_declined' and d['items'][0]['title'] == 'Olive declined your request'" "N2 gets request_declined from Olive"
check "d['items'][0]['request_id'] == $NR2 and d['items'][0]['listing_id'] == $NL1 and d['items'][0]['body'] == '$NT_T1'" "declined points at N2's request and NL1"
nts "$TOK_NO"
check "d['total'] == 3 and d['unread'] == 2 and [n['read'] for n in d['items'] if n['request_id'] == $NR2] == [True]" "owner: nothing new, the declined request's notification is read"

# Accept N1 -> N1 gets request_accepted, N3 is auto-declined.
sleep 1
req POST "/requests/$NR1/accept" "" "$TOK_NO"; [[ "$STATUS" == 200 ]] || fail "owner accepts N1"
nts "$TOK_N1"
check "d['total'] == 1 and d['items'][0]['type'] == 'request_accepted' and d['items'][0]['title'] == 'Olive accepted your request' and d['items'][0]['request_id'] == $NR1 and d['items'][0]['body'] == '$NT_T1'" "N1 gets request_accepted"
nts "$TOK_N3"
check "d['total'] == 1 and d['items'][0]['type'] == 'request_declined' and d['items'][0]['request_id'] == $NR3 and d['items'][0]['title'] == 'Olive gave this one to someone else'" "auto-declined N3 gets request_declined"
nts "$TOK_N2"
check "d['total'] == 1" "N2 (already declined) gets nothing more"
nts "$TOK_NO"
check "d['total'] == 3 and d['unread'] == 0 and all(n['read'] for n in d['items'])" "owner: accept and auto-decline mark all request_received read, nothing new"

# Messages: N1 -> owner; a second unread message collapses into the same notification.
req POST "/requests/$NR1/messages" '{"body": "Hi Olive, is noon ok?"}' "$TOK_N1"; [[ "$STATUS" == 201 ]] || fail "N1 messages"
nts "$TOK_NO"
check "d['total'] == 4 and d['unread'] == 1 and d['items'][0]['type'] == 'new_message' and d['items'][0]['title'] == 'Rex sent you a message' and d['items'][0]['body'] == 'Hi Olive, is noon ok?'" "owner gets new_message from Rex with the text"
check "d['items'][0]['request_id'] == $NR1 and d['items'][0]['listing_id'] == $NL1" "new_message points at the request"
NM1="$(jget "d['items'][0]['id']")"; NM1_AT="$(jget "d['items'][0]['created_at']")"
nts "$TOK_N1"
check "d['total'] == 1" "the sender isn't notified about their own message"
sleep 1
req POST "/requests/$NR1/messages" '{"body": "Or 1pm works too"}' "$TOK_N1"; [[ "$STATUS" == 201 ]] || fail "N1 messages again"
nts "$TOK_NO"
check "d['total'] == 4 and d['unread'] == 1 and d['items'][0]['id'] == $NM1" "second unread message collapses into the same notification"
check "d['items'][0]['title'] == 'Rex sent you 2 messages' and d['items'][0]['body'] == 'Or 1pm works too' and d['items'][0]['created_at'] > '$NM1_AT'" "collapsed: count in title, newest text, created_at bumped"
req GET /me/unread "" "$TOK_NO"
check "d['notifications'] == 1 and d['messages'] == 2" "owner /me/unread: 1 notification, 2 messages"

# The owner replies -> her new_message is read; N1 gets one.
req POST "/requests/$NR1/messages" '{"body": "Noon at Commons!"}' "$TOK_NO"; [[ "$STATUS" == 201 ]] || fail "owner replies"
nts "$TOK_NO"
check "d['total'] == 4 and d['unread'] == 0" "replying marks the owner's new_message read"
nts "$TOK_N1"
check "d['total'] == 2 and d['unread'] == 2 and d['items'][0]['type'] == 'new_message' and d['items'][0]['title'] == 'Olive sent you a message'" "N1 gets new_message from Olive"
NM2="$(jget "d['items'][0]['id']")"
sleep 1
req POST "/requests/$NR1/messages" '{"body": "See you"}' "$TOK_NO"; [[ "$STATUS" == 201 ]] || fail "owner messages again"
nts "$TOK_N1"
check "d['total'] == 2 and d['items'][0]['id'] == $NM2 and d['items'][0]['title'] == 'Olive sent you 2 messages'" "N1's new_message collapses too"
# Reading the chat marks N1's new_message read; the next message starts a new one.
req GET "/requests/$NR1/messages" "" "$TOK_N1"; [[ "$STATUS" == 200 ]] || fail "N1 reads the chat"
nts "$TOK_N1"
check "d['total'] == 2 and d['unread'] == 1 and [n['read'] for n in d['items'] if n['id'] == $NM2] == [True]" "reading the chat marks N1's new_message read"
sleep 1
LONG="$(python3 -c 'print(" ".join(["word"] * 80))')"
req POST "/requests/$NR1/messages" "{\"body\": \"$LONG\"}" "$TOK_NO"; [[ "$STATUS" == 201 ]] || fail "owner sends a long message"
nts "$TOK_N1"
check "d['total'] == 3 and d['unread'] == 2 and d['items'][0]['id'] != $NM2 and d['items'][0]['title'] == 'Olive sent you a message'" "after reading, a new message makes a new notification"
check "len(d['items'][0]['body']) <= 140 and d['items'][0]['body'].endswith('…')" "long message body is a short preview"
req GET /me/unread "" "$TOK_N1"
check "d['notifications'] == 2" "N1 /me/unread notifications 2"

# Complete and cancel send no request notifications. Completing a first exchange earns
# First Swap (S-22), so each side gets exactly one badge_earned; both mark it read.
req POST "/requests/$NR1/complete" "" "$TOK_N1"; [[ "$STATUS" == 200 ]] || fail "N1 completes"
nts "$TOK_NO"
check "d['total'] == 5 and d['unread'] == 1 and d['items'][0]['type'] == 'badge_earned' and d['items'][0]['request_id'] is None" "complete: the owner only gets First Swap"
req POST /notifications/read "{\"ids\": [$(jget "d['items'][0]['id']")]}" "$TOK_NO"; [[ "$STATUS" == 204 ]] || fail "owner reads the badge notification"
nts "$TOK_N1"
check "d['total'] == 4 and d['items'][0]['type'] == 'badge_earned' and [n['type'] for n in d['items'][1:]] == ['new_message', 'new_message', 'request_accepted']" "complete: the requester only gets First Swap"
req POST /notifications/read "{\"ids\": [$(jget "d['items'][0]['id']")]}" "$TOK_N1"; [[ "$STATUS" == 204 ]] || fail "N1 reads the badge notification"
sleep 1
req POST "/listings/$NL2/requests" '{}' "$TOK_N2"; [[ "$STATUS" == 201 ]] || fail "N2 requests NL2"
NR4="$(jget 'd["id"]')"
nts "$TOK_NO"; check "d['total'] == 6 and d['unread'] == 1 and d['items'][0]['request_id'] == $NR4" "N2's request on NL2 notifies the owner"
req POST "/requests/$NR4/cancel" "" "$TOK_N2"; [[ "$STATUS" == 200 ]] || fail "N2 cancels pending"
nts "$TOK_NO"; check "d['total'] == 6" "cancel (pending): nothing for the owner"
req POST "/listings/$NL2/requests" '{}' "$TOK_N3"; [[ "$STATUS" == 201 ]] || fail "N3 requests NL2"
NR5="$(jget 'd["id"]')"
req POST "/requests/$NR5/accept" "" "$TOK_NO"; [[ "$STATUS" == 200 ]] || fail "owner accepts N3 on NL2"
req POST "/requests/$NR5/cancel" "" "$TOK_N3"; [[ "$STATUS" == 200 ]] || fail "N3 cancels accepted"
nts "$TOK_NO"; check "d['total'] == 7 and not any(n['type'] not in ('request_received', 'new_message', 'badge_earned') for n in d['items'])" "cancel (accepted): owner got only the request_received"
nts "$TOK_N3"; check "d['total'] == 2 and d['items'][0]['type'] == 'request_accepted' and d['items'][0]['request_id'] == $NR5" "N3: declined earlier, now accepted, nothing for the cancel"
nts "$TOK_N2"; check "d['total'] == 1" "N2: nothing for its own cancel"

# Mark read: some IDs, someone else's IDs, then all.
nts "$TOK_N1"
N1_UNREAD="$(jget "[n['id'] for n in d['items'] if not n['read']]")"
N1_FIRST="$(jget "[n['id'] for n in d['items'] if not n['read']][0]")"
check "len($N1_UNREAD) == 2" "N1 has 2 unread before marking"
req POST /notifications/read "{\"ids\": [$N1_FIRST]}" "$TOK_N2"
expect 204 "someone else's ID is ignored (still 204)"
nts "$TOK_N1"; check "d['unread'] == 2" "N1's notification is still unread"
req POST /notifications/read "{\"ids\": [$N1_FIRST, 999999999]}" "$TOK_N1"
expect 204 "POST /notifications/read with ids"
[[ ! -s "$BODY" ]] || fail "mark-read 204 has an empty body"
ok "mark-read body is empty"
nts "$TOK_N1"
check "d['unread'] == 1 and [n['read'] for n in d['items'] if n['id'] == $N1_FIRST] == [True] and d['total'] == 4" "only that ID is read"
req POST /notifications/read "{\"ids\": [$N1_FIRST]}" "$TOK_N1"
expect 204 "marking it again is still 204"
nts "$TOK_N1"; check "d['unread'] == 1" "idempotent"
req POST /notifications/read '{"ids": []}' "$TOK_N1"
expect 204 "empty ids is a no-op 204"
req GET /me/unread "" "$TOK_N1"
check "d['notifications'] == 1" "/me/unread agrees: 1"
req POST /notifications/read '{}' "$TOK_N1"
expect 400 bad_request "mark-read with neither ids nor all"
req POST /notifications/read '{"all": false}' "$TOK_N1"
expect 400 bad_request "mark-read with all false"
req POST /notifications/read '{"ids": "x"}' "$TOK_N1"
expect 400 bad_request "mark-read with ids not a list"
req POST /notifications/read "" "$TOK_N1"
expect 400 bad_request "mark-read with no body"
req POST /notifications/read '{"all": true}' "$TOK_N1"
expect 204 "POST /notifications/read all"
nts "$TOK_N1"; check "d['unread'] == 0 and all(n['read'] for n in d['items']) and d['total'] == 4" "all read, nothing deleted"
req GET /me/unread "" "$TOK_N1"
check "d['notifications'] == 0" "/me/unread notifications 0"
nts "$TOK_NO"; check "d['unread'] == 1" "marking all for N1 didn't touch the owner's"

# ---------------------------------------------------------------------------
section "badges (S-22)"
# Fresh users: giver BG (Gwen), receiver BR (Remy). Rules (docs/API.md GET /me/badges):
# first_swap = 1 completed exchange either side; giving_back = 5 of my donate listings
# completed; closet_cleanout = 10 listings created, deleted ones included.
BADGE_KEYS="{'id','name','description','earned_at','progress','goal'}"
BADGE_ORDER="['first_swap', 'giving_back', 'closet_cleanout']"
# bdg TOKEN -> GET /me/badges into $BODY, checks the shape; B = {id: badge} in checks
bdg() {
  req GET /me/badges "" "$1"; [[ "$STATUS" == 200 ]] || fail "GET /me/badges"
  check "[b['id'] for b in d['items']] == $BADGE_ORDER and all(set(b) == $BADGE_KEYS for b in d['items']) and [b['goal'] for b in d['items']] == [1, 5, 10] and all(0 <= b['progress'] <= b['goal'] and (b['earned_at'] is None or ISO.match(b['earned_at'])) for b in d['items'])" "badges: all 3 in order, contract keys, goals 1/5/10" >/dev/null
}
# bcheck EXPR DESC -> check with B = {id: badge} from the last bdg
bcheck() { check "(lambda B: $1)({b['id']: b for b in d['items']})" "$2"; }
# badge_notes TOKEN -> prints the number of badge_earned notifications
badge_notes() {
  nts "$1"; jget "len([n for n in d['items'] if n['type'] == 'badge_earned'])"
}
b_list() {  # b_list TOKEN TITLE SHARE_TYPE -> prints a new listing id
  local photo; photo="$(up "$SMALL_JPEG" front "$1")" || exit 1
  req POST /listings "{\"title\": \"$2\", \"category\": \"tops\", \"condition\": \"good\", \"share_type\": \"$3\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$photo]}" "$1"
  [[ "$STATUS" == 201 ]] || fail "list $2"
  jget 'd["id"]'
}
b_swap() {  # b_swap LISTING_ID -> BR requests it, BG accepts, BG marks it done
  req POST "/listings/$1/requests" '{}' "$TOK_BR"; [[ "$STATUS" == 201 ]] || fail "BR requests $1"
  local rid; rid="$(jget 'd["id"]')"
  req POST "/requests/$rid/accept" "" "$TOK_BG"; [[ "$STATUS" == 200 ]] || fail "BG accepts $rid"
  req POST "/requests/$rid/complete" "" "$TOK_BG"; [[ "$STATUS" == 200 ]] || fail "BG completes $rid"
}
read -r TOK_BG USR_BG <<<"$(nt_user bg "Gwen Smoke")" || exit 1
read -r TOK_BR USR_BR <<<"$(nt_user br "Remy Smoke")" || exit 1
[[ -n "$TOK_BG" && -n "$TOK_BR" ]] || fail "set up badge users"
ok "2 fresh users for badges"

req GET /me/badges
expect 401 unauthorized "GET /me/badges without a token"
req GET /me/badges "" "$TOK_BG"
expect 200 "GET /me/badges"
check "len(d) == 1 and len(d['items']) == 3" "body is {items: [3 badges]}"
bdg "$TOK_BG"
check "d['items'] == [{'id': 'first_swap', 'name': 'First Swap', 'description': 'Complete your first exchange', 'earned_at': None, 'progress': 0, 'goal': 1}, {'id': 'giving_back', 'name': 'Giving Back', 'description': 'Donate five items', 'earned_at': None, 'progress': 0, 'goal': 5}, {'id': 'closet_cleanout', 'name': 'Closet Cleanout', 'description': 'List ten items', 'earned_at': None, 'progress': 0, 'goal': 10}]" "new user: exact names/descriptions, nothing earned, progress 0"

# Listings: 1 -> progress 1, nothing earned yet.
BL1="$(b_list "$TOK_BG" "Badge tee 1 $MK" donate)" || exit 1
bdg "$TOK_BG"
bcheck "B['closet_cleanout']['progress'] == 1 and B['closet_cleanout']['earned_at'] is None and B['first_swap']['progress'] == 0" "first listing: Closet Cleanout 1 of 10, not earned"
[[ "$(badge_notes "$TOK_BG")" == 0 ]] || fail "no badge notification after one listing"
ok "no badge_earned notification after one listing"
BL_IDS="$BL1"
for i in 2 3 4 5 6 7 8 9; do
  lid="$(b_list "$TOK_BG" "Badge tee $i $MK" donate)" || exit 1
  BL_IDS="$BL_IDS $lid"
done
bdg "$TOK_BG"
bcheck "B['closet_cleanout']['progress'] == 9 and B['closet_cleanout']['earned_at'] is None" "9 listings: 9 of 10"
# Delete one: still counts (listings created, deleted included).
DEL_ID="${BL_IDS##* }"; BL_IDS="${BL_IDS% *}"
req DELETE "/listings/$DEL_ID" "" "$TOK_BG"; expect 204 "delete one of the 9 listings"
bdg "$TOK_BG"
bcheck "B['closet_cleanout']['progress'] == 9" "a deleted listing still counts (9 of 10)"
BL10="$(b_list "$TOK_BG" "Badge tee 10 $MK" donate)" || exit 1
BL_IDS="$BL_IDS $BL10"
bdg "$TOK_BG"
bcheck "B['closet_cleanout']['progress'] == 10 and ISO.match(B['closet_cleanout']['earned_at']) and B['first_swap']['earned_at'] is None and B['giving_back']['earned_at'] is None" "10th listing earns Closet Cleanout (10 of 10, earned_at set)"
CC_AT="$(jget "d['items'][2]['earned_at']")"
nts "$TOK_BG"
check "d['total'] == 1 and d['unread'] == 1 and set(d['items'][0]) == $NOTIF_KEYS" "one notification for the giver"
check "d['items'][0]['type'] == 'badge_earned' and d['items'][0]['title'] == 'You earned Closet Cleanout' and d['items'][0]['body'] == 'List ten items' and d['items'][0]['request_id'] is None and d['items'][0]['listing_id'] is None and d['items'][0]['read'] is False" "badge_earned: title, body, both IDs null, unread"
req GET /me/unread "" "$TOK_BG"
check "d['notifications'] == 1" "/me/unread counts the badge notification"
sleep 1
BL11="$(b_list "$TOK_BG" "Badge tee 11 $MK" swap)" || exit 1
bdg "$TOK_BG"
bcheck "B['closet_cleanout']['progress'] == 10 and B['closet_cleanout']['earned_at'] == '$CC_AT'" "11th listing: progress stops at 10, earned_at unchanged"
[[ "$(badge_notes "$TOK_BG")" == 1 ]] || fail "11th listing re-sent Closet Cleanout"
ok "11th listing: no duplicate badge notification"
bdg "$TOK_BR"
bcheck "all(b['earned_at'] is None and b['progress'] == 0 for b in B.values())" "the receiver has nothing yet"

# Exchanges: the first earns First Swap for both sides; donations count toward Giving Back.
read -r -a BL <<<"$BL_IDS"
b_swap "${BL[0]}"
bdg "$TOK_BG"
bcheck "ISO.match(B['first_swap']['earned_at']) and B['first_swap']['progress'] == 1 and B['giving_back']['progress'] == 1 and B['giving_back']['earned_at'] is None" "giver: First Swap earned, Giving Back 1 of 5"
bdg "$TOK_BR"
bcheck "ISO.match(B['first_swap']['earned_at']) and B['giving_back']['progress'] == 0 and B['closet_cleanout']['progress'] == 0" "receiver: First Swap earned, receiving doesn't count as giving"
nts "$TOK_BR"
check "d['items'][0]['type'] == 'badge_earned' and d['items'][0]['title'] == 'You earned First Swap' and d['items'][0]['body'] == 'Complete your first exchange' and d['items'][0]['request_id'] is None" "receiver gets a First Swap notification"
[[ "$(badge_notes "$TOK_BR")" == 1 ]] || fail "receiver should have 1 badge notification"
[[ "$(badge_notes "$TOK_BG")" == 2 ]] || fail "giver should have 2 badge notifications"
ok "one badge_earned each for First Swap"
bdg "$TOK_BG"; FS_AT="$(jget "d['items'][0]['earned_at']")"
b_swap "${BL[1]}"; b_swap "${BL[2]}"; b_swap "${BL[3]}"
bdg "$TOK_BG"
bcheck "B['giving_back']['progress'] == 4 and B['giving_back']['earned_at'] is None and B['first_swap']['earned_at'] == '$FS_AT'" "4 donations: Giving Back 4 of 5, First Swap not re-earned"
[[ "$(badge_notes "$TOK_BG")" == 2 && "$(badge_notes "$TOK_BR")" == 1 ]] || fail "more exchanges duplicated First Swap"
ok "more exchanges: no duplicate First Swap rows or notifications"
# A swap (not donate) listing completed doesn't count toward Giving Back.
b_swap "$BL11"
bdg "$TOK_BG"
bcheck "B['giving_back']['progress'] == 4" "a completed swap listing doesn't count as a donation"
b_swap "${BL[4]}"
bdg "$TOK_BG"
bcheck "all(ISO.match(b['earned_at']) and b['progress'] == b['goal'] for b in B.values())" "5th donation earns Giving Back: the giver has all 3"
nts "$TOK_BG"
check "[n['title'] for n in d['items'] if n['type'] == 'badge_earned'] == ['You earned Giving Back', 'You earned First Swap', 'You earned Closet Cleanout']" "giver's 3 badge notifications, newest first"
b_swap "${BL[5]}"
[[ "$(badge_notes "$TOK_BG")" == 3 ]] || fail "6th donation re-sent a badge"
ok "6th donation: still exactly 3 badge notifications"
bdg "$TOK_BG"
bcheck "B['giving_back']['progress'] == 5" "Giving Back progress stops at 5"
bdg "$TOK_BR"
bcheck "B['first_swap']['progress'] == 1 and B['giving_back']['earned_at'] is None and B['closet_cleanout']['earned_at'] is None" "receiver still has only First Swap"

# ---------------------------------------------------------------------------
section "reports and hidden listings (S-24)"
# Fresh users: owner RO, reporters R1, R2, R3 (all smoke.edu). RO's listing L_RP gets
# three reports and becomes hidden; then every hidden rule is checked from both sides.
# R3's listing L_RS shares L_RP's tag, so L_RP shows up in L_RS's similar row.
rp_list() {  # rp_list TOKEN TITLE -> prints a new listing id (category bags, tag rptag)
  local photo; photo="$(up "$SMALL_JPEG" front "$1")" || exit 1
  req POST /listings "{\"title\": \"$2\", \"category\": \"bags\", \"condition\": \"good\", \"share_type\": \"free\", \"tags\": [\"rptag${RUN}\"], \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$photo]}" "$1"
  [[ "$STATUS" == 201 ]] || fail "list $2"
  jget 'd["id"]'
}
read -r TOK_RO ID_RO <<<"$(nt_user rpo Rory)" || exit 1
read -r TOK_R1 ID_R1 <<<"$(nt_user rp1)" || exit 1
read -r TOK_R2 ID_R2 <<<"$(nt_user rp2)" || exit 1
read -r TOK_R3 ID_R3 <<<"$(nt_user rp3)" || exit 1
ok "4 fresh users: owner and 3 reporters"
L_RP="$(rp_list "$TOK_RO" "Report me tote $MK")" || exit 1
sleep 1
L_RS="$(rp_list "$TOK_R3" "Similar tote $MK")" || exit 1
ok "owner listed L_RP, R3 listed a similar L_RS"

# Before any report: R1 has a pending request, R2 has it saved, it's in feed and similar.
req POST "/listings/$L_RP/requests" '{}' "$TOK_R1"
expect 201 "R1 requests L_RP (stays pending)"
RQ_RP="$(jget 'd["id"]')"
req PUT "/listings/$L_RP/save" "" "$TOK_R2"
expect 204 "R2 saves L_RP"
req GET /me/saved "" "$TOK_R2"
check "[l['id'] for l in d['items']] == [$L_RP]" "L_RP is in R2's saved list"
req GET "/listings/$L_RS/similar" "" "$TOK_R1"
check "$L_RP in [l['id'] for l in d['items']]" "L_RP is in L_RS's similar row"

# Errors.
req POST "/listings/$L_RP/report" '{}'
expect 401 unauthorized "report without a token"
req POST "/listings/$L_RP/report" '{"reason": "mine"}' "$TOK_RO"
expect 409 own_listing "reporting your own listing"
req POST /listings/999999999/report '{}' "$TOK_R1"
expect 404 not_found "report a missing listing"
req POST "/listings/$L_RP/report" '{}' "$TOKEN_C"
expect 404 not_found "report another campus's listing"
LONG201="$(python3 -c 'print("x" * 201)')"
req POST "/listings/$L_RP/report" "{\"reason\": \"$LONG201\"}" "$TOK_R1"
expect 400 bad_request "reason over 200 characters"
check "'reason' in d['error']['message']" "the 400 names reason"
req POST "/listings/$L_RP/report" '{"reason": 5}' "$TOK_R1"
expect 400 bad_request "reason that isn't a string"

# Reports 1 and 2 (R1 twice counts once): still visible.
LONG200="$(python3 -c 'print("y" * 200)')"
req POST "/listings/$L_RP/report" "{\"reason\": \"$LONG200\"}" "$TOK_R1"
expect 204 "R1 reports (200-char reason)"
[[ ! -s "$BODY" ]] || fail "report body should be empty"
ok "report body is empty"
req POST "/listings/$L_RP/report" '{"reason": "Not clothing"}' "$TOK_R1"
expect 204 "R1 reports again: 204, counts once"
req POST "/listings/$L_RP/report" '{}' "$TOK_R2"
expect 204 "R2 reports (empty body)"
req GET "/listings/$L_RP" "" "$TOK_R3"
expect 200 "2 reporters (one twice): still visible"
check "d['status'] == 'active'" "still active after 2 distinct reporters"
req GET "/listings?q=rptag${RUN}" "" "$TOK_R3"
check "$L_RP in [l['id'] for l in d['items']]" "still in the feed after 2 reporters"

# Report 3 hides it.
req POST "/listings/$L_RP/report" "" "$TOK_R3"
expect 204 "R3 reports (no body): third distinct reporter"

# Owner still sees it.
req GET "/listings/$L_RP" "" "$TOK_RO"
expect 200 "owner GET hidden listing"
check "d['status'] == 'hidden' and d['is_mine'] is True" "owner sees status hidden"
req GET /me/listings "" "$TOK_RO"
check "any(l['id'] == $L_RP and l['status'] == 'hidden' for l in d['items'])" "owner's /me/listings (active tab) includes it"
req GET "/listings?q=rptag${RUN}" "" "$TOK_RO"
check "$L_RP not in [l['id'] for l in d['items']]" "not in the owner's feed either"
req POST "/listings/$L_RP/report" '{}' "$TOK_RO"
expect 409 own_listing "owner reporting own hidden listing"

# Everyone else: 404 everywhere, gone from lists.
for who in R1 R2 R3; do
  tokvar="TOK_$who"; tok="${!tokvar}"
  req GET "/listings/$L_RP" "" "$tok"
  expect 404 not_found "$who: GET hidden listing"
done
req GET "/listings/$L_RP/similar" "" "$TOK_R1"
expect 404 not_found "similar on a hidden listing"
req POST "/listings/$L_RP/style" "" "$TOK_R1"
expect 404 not_found "style on a hidden listing"
req PUT "/listings/$L_RP/save" "" "$TOK_R1"
expect 404 not_found "save a hidden listing"
req DELETE "/listings/$L_RP/save" "" "$TOK_R2"
expect 404 not_found "unsave a hidden listing"
req POST "/listings/$L_RP/requests" '{}' "$TOK_R2"
expect 404 not_found "request a hidden listing"
req POST "/listings/$L_RP/report" '{}' "$TOK_R2"
expect 404 not_found "report a hidden listing (already reported)"
req POST "/listings/$L_RP/report" '{}' "$TOKEN_A"
expect 404 not_found "report a hidden listing (new reporter)"
req GET "/listings?q=rptag${RUN}" "" "$TOK_R1"
check "[l['id'] for l in d['items']] == [$L_RS]" "feed search: only L_RS left"
req GET "/listings?limit=100" "" "$TOK_R1"
check "$L_RP not in [l['id'] for l in d['items']]" "not in the unfiltered feed"
req GET /me/saved "" "$TOK_R2"
check "d['items'] == [] and d['total'] == 0" "gone from R2's saved list"
req GET "/listings/$L_RS/similar" "" "$TOK_R1"
expect 200 "similar for L_RS"
check "$L_RP not in [l['id'] for l in d['items']]" "gone from L_RS's similar row"

# Open requests are left alone: the owner can't accept, the requester can still cancel.
req GET "/requests/$RQ_RP" "" "$TOK_R1"
expect 200 "R1 still sees the request"
check "d['status'] == 'pending'" "the request is still pending"
req POST "/requests/$RQ_RP/accept" "" "$TOK_RO"
expect 409 wrong_status "owner can't accept on a hidden listing"
req POST "/requests/$RQ_RP/cancel" "" "$TOK_R1"
expect 200 "R1 cancels the pending request"
req GET "/listings/$L_RP" "" "$TOK_RO"
check "d['status'] == 'hidden'" "still hidden after the cancel"

# A pending listing (accepted request) is hidden too, and cancelling doesn't unhide it.
L_RQ="$(rp_list "$TOK_RO" "Report pending tote $MK")" || exit 1
req POST "/listings/$L_RQ/requests" '{}' "$TOK_R1"
expect 201 "R1 requests L_RQ"
RQ_RQ="$(jget 'd["id"]')"
req POST "/requests/$RQ_RQ/accept" "" "$TOK_RO"
expect 200 "owner accepts: L_RQ is pending"
for who in R1 R2 R3; do
  tokvar="TOK_$who"
  req POST "/listings/$L_RQ/report" '{}' "${!tokvar}"
  [[ "$STATUS" == 204 ]] || fail "$who reports L_RQ"
done
ok "3 reporters on the pending listing"
req GET "/listings/$L_RQ" "" "$TOK_RO"
check "d['status'] == 'hidden'" "pending listing hidden after 3 reports"
req POST "/requests/$RQ_RQ/cancel" "" "$TOK_R1"
expect 200 "R1 cancels the accepted request"
req GET "/listings/$L_RQ" "" "$TOK_RO"
check "d['status'] == 'hidden'" "cancelling an accepted request doesn't unhide it"
req GET "/listings/$L_RQ" "" "$TOK_R2"
expect 404 not_found "still 404 for others"

# ---------------------------------------------------------------------------
section "events and donation bins (S-27)"
EVENT_KEYS="{'id','title','description','kind','status','is_live','starts_at','ends_at','location_name','lat','lng'}"
BIN_KEYS="{'id','name','description','accepts','hours','lat','lng'}"
# EVENTS_OK: contract shape, enums, is_live == (status == live), sorted by (starts_at, id).
EVENTS_OK="list(d) == ['items'] and all(set(e) == $EVENT_KEYS and type(e['id']) is int and e['title'] and e['location_name'] and e['kind'] in ('swap_day', 'donation_drive', 'repair_workshop') and e['status'] in ('upcoming', 'live', 'ended') and e['is_live'] is (e['status'] == 'live') and ISO.match(e['starts_at']) and ISO.match(e['ends_at']) and e['starts_at'] < e['ends_at'] and (e['lat'] is None) == (e['lng'] is None) for e in d['items']) and [(e['starts_at'], e['id']) for e in d['items']] == sorted((e['starts_at'], e['id']) for e in d['items'])"
BINS_OK="list(d) == ['items'] and all(set(b) == $BIN_KEYS and type(b['id']) is int and b['name'] and isinstance(b['lat'], (int, float)) and isinstance(b['lng'], (int, float)) for b in d['items']) and [(b['name'], b['id']) for b in d['items']] == sorted((b['name'], b['id']) for b in d['items'])"
req GET /events
expect 401 unauthorized "GET /events without a token"
req GET "/events?include_past=true"
expect 401 unauthorized "GET /events?include_past=true without a token"
req GET /donation-bins
expect 401 unauthorized "GET /donation-bins without a token"
req GET /events "" "$TOKEN_A"
expect 200 "GET /events on smoke.edu"
check "d == {'items': []}" "smoke.edu has no events (campus-scoped, none of Vanderbilt's)"
req GET "/events?include_past=true" "" "$TOKEN_A"
expect 200 "GET /events?include_past=true on smoke.edu"
check "d == {'items': []}" "smoke.edu has no past events either"
req GET "/events?include_past=false&limit=1&offset=5" "" "$TOKEN_A"
expect 200 "GET /events ignores limit/offset"
req GET "/events?include_past=maybe" "" "$TOKEN_A"
expect 400 bad_request "GET /events?include_past=maybe"
req GET /donation-bins "" "$TOKEN_A"
expect 200 "GET /donation-bins on smoke.edu"
check "d == {'items': []}" "smoke.edu has no donation bins"
req GET /events "" "$TOKEN_C"
check "d == {'items': []}" "another campus has no events"

# ---------------------------------------------------------------------------
section "demo campus vanderbilt.edu (S-15, read-only)"
# READ-ONLY on purpose: the demo data must survive smoke runs. Logging in only adds a
# session row. Never call GET /requests/{id}/messages here (it moves read markers), and
# keep the checks loose enough to pass while people are clicking through the demo.
# SKIP_DEMO=1 skips this section (e.g. against a dev server with no seed).
if [[ "${SKIP_DEMO:-}" == 1 ]]; then
  echo "  (skipped: SKIP_DEMO=1)"
else
  SIZE_VOCAB="{'XS','S','M','L','XL','XXL','One size'} | {str(n) for n in range(24, 41)} | {f'{h/2:g}' for h in range(10, 29)}"
  for who in jordan.park sam.lee riley.chen; do
    req POST /auth/login "{\"email\": \"$who@vanderbilt.edu\"}"
    expect 200 "log in as demo account $who"
    check "d['is_new'] is False and d['user']['name'] and d['user']['dorm'] and d['user']['class_year']" "$who has a seeded profile"
    check "d['user']['campus']['name'] == 'Vanderbilt' and all(d['user']['sizes'].values())" "$who: campus Vanderbilt, sizes set"
    tok="$(jget 'd["token"]')"
    case "$who" in
      jordan.park) DEMO_J="$tok" ;; sam.lee) DEMO_S="$tok" ;; riley.chen) DEMO_R="$tok" ;;
    esac
  done
  req GET /me "" "$DEMO_J"
  check "d['name'] == 'Jordan Park' and d['email'] == 'jordan.park@vanderbilt.edu'" "GET /me is Jordan Park"

  req GET /dorms "" "$DEMO_J"
  expect 200 "demo /dorms"
  check "len(d['items']) >= 6 and 'Kissam' in d['items'] and d['items'] == sorted(d['items'])" "6+ dorms incl. Kissam, sorted"
  req GET /meetup-spots "" "$DEMO_J"
  expect 200 "demo /meetup-spots"
  check "len(d['items']) >= 6 and 'Commons Center' in [s['name'] for s in d['items']]" "6+ spots incl. Commons Center"

  req GET /meetup-spots "" "$DEMO_J"
  check "all(isinstance(s['lat'], float) and isinstance(s['lng'], float) and 36.138 <= s['lat'] <= 36.152 and -86.810 <= s['lng'] <= -86.794 for s in d['items'])" "every Vanderbilt meetup spot has lat/lng on campus (S-27)"
  req GET /events "" "$DEMO_J"
  expect 200 "demo /events"
  check "$EVENTS_OK" "demo events: contract shape, enums, sorted by starts_at"
  check "sum(e['status'] == 'upcoming' for e in d['items']) >= 2 and sum(e['is_live'] for e in d['items']) >= 1" "2+ upcoming demo events and one live now"
  check "any(e['kind'] == 'swap_day' and e['status'] == 'upcoming' for e in d['items']) and {'swap_day', 'donation_drive', 'repair_workshop'} <= {e['kind'] for e in d['items']}" "an upcoming Swap Day, plus a drive and a workshop"
  NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  DAY_AGO="$(python3 -c 'import datetime as t; print((t.datetime.now(t.UTC) - t.timedelta(days=1, minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  check "all((e['status'] == 'upcoming') == ('$NOW_ISO' < e['starts_at']) and (e['status'] == 'ended') == (e['ends_at'] <= '$NOW_ISO') for e in d['items'])" "event status matches its times against now"
  check "all(e['ends_at'] >= '$DAY_AGO' for e in d['items'])" "default list: nothing that ended more than a day ago"
  check "all(e['lat'] is not None and 36.138 <= e['lat'] <= 36.152 and -86.810 <= e['lng'] <= -86.794 for e in d['items'])" "demo events are pinned on campus"
  DEMO_EVENTS="$(jget "[e['id'] for e in d['items']]")"
  req GET "/events?include_past=true" "" "$DEMO_J"
  expect 200 "demo /events?include_past=true"
  check "$EVENTS_OK" "include_past: same shape and order"
  check "set($DEMO_EVENTS) < {e['id'] for e in d['items']}" "include_past is a superset of the default list"
  check "any(e['status'] == 'ended' and e['ends_at'] < '$DAY_AGO' and e['id'] not in $DEMO_EVENTS for e in d['items'])" "include_past adds an event that ended 2 days ago"
  req GET /donation-bins "" "$DEMO_J"
  expect 200 "demo /donation-bins"
  check "$BINS_OK" "demo bins: contract shape, sorted by name"
  check "len(d['items']) >= 3 and all(36.138 <= b['lat'] <= 36.152 and -86.810 <= b['lng'] <= -86.794 for b in d['items'])" "3+ demo bins with coordinates on campus"
  DEMO_BINS="$(jget "[b['id'] for b in d['items']]")"
  req GET /donation-bins "" "$TOKEN_A"
  check "not ({b['id'] for b in d['items']} & set($DEMO_BINS))" "smoke.edu sees none of Vanderbilt's bins"
  req GET "/events?include_past=true" "" "$TOKEN_A"
  check "not ({e['id'] for e in d['items']} & set($DEMO_EVENTS))" "smoke.edu sees none of Vanderbilt's events"

  req GET "/listings?limit=50" "" "$DEMO_J"
  expect 200 "demo feed"
  check "d['total'] >= 20 and len(d['items']) >= 20" "feed has 20+ listings"
  check "all(l['status'] == 'active' and l['photos'] and l['photos'][0]['url'].startswith('http') for l in d['items'])" "every feed listing is active with a photo URL"
  check "len({l['owner']['id'] for l in d['items']}) >= 6 and any(l['is_mine'] for l in d['items']) and any(not l['is_mine'] for l in d['items'])" "feed mixes owners, incl. Jordan's own"
  check "len({l['category'] for l in d['items']}) >= 5 and len({l['share_type'] for l in d['items']}) >= 2" "feed spans 5+ categories and 2+ share types"
  check "all(l['size'] in ($SIZE_VOCAB) for l in d['items'] if l['size'] is not None)" "feed sizes use the IOS-2 vocabulary"
  check "[l['created_at'] for l in d['items']] == sorted((l['created_at'] for l in d['items']), reverse=True)" "feed newest first"
  check "sum(1 for l in d['items'] if l['condition_note']) >= 4" "4+ demo feed listings have a condition_note (S-28)"
  check "all(l['condition_note'] is None or (0 < len(l['condition_note']) <= 140 and not l['condition_note'].endswith('.') and l['condition'] != 'new') for l in d['items'])" "demo condition_notes are short, no period, none on new items"
  DEMO_LID="$(jget "d['items'][0]['id']")"
  DEMO_OWNERS="$(jget "sorted({l['owner']['id'] for l in d['items']})")"
  for idx in 0 7 15; do
    url="$(jget "d['items'][$idx]['photos'][0]['url']")"
    fetch "$url" "$TMP/demo_photo.jpg"
    [[ "$STATUS" == 200 && "$CTYPE" == image/jpeg* ]] || fail "demo photo $url (HTTP $STATUS $CTYPE)"
    ok "feed photo $idx loads (200 image/jpeg, $(jpeg_size "$TMP/demo_photo.jpg"))"
  done

  req GET "/me/requests?role=incoming" "" "$DEMO_J"
  expect 200 "Jordan's incoming requests"
  check "d['total'] >= 3 and all(r['owner']['id'] != r['requester']['id'] for r in d['items'])" "Jordan has 3+ incoming requests"
  check "any(r['status'] in ('accepted', 'completed') for r in d['items'])" "incoming has an accepted or completed exchange"
  req GET "/me/requests?role=outgoing" "" "$DEMO_J"
  expect 200 "Jordan's outgoing requests"
  check "d['total'] >= 1" "Jordan has an outgoing request"
  req GET /me/unread "" "$DEMO_J"
  expect 200 "Jordan's /me/unread"
  check "all(isinstance(d[k], int) and d[k] >= 0 for k in ('notifications', 'messages', 'incoming_requests'))" "unread counts are numbers"
  check "d['notifications'] >= 2" "Jordan's bell has 2+ unread"
  req GET "/notifications?limit=50" "" "$DEMO_J"
  expect 200 "Jordan's /notifications (read-only: never marked read here)"
  check "d['unread'] >= 2 and d['total'] >= 5 and all(set(n) == $NOTIF_KEYS and ISO.match(n['created_at']) for n in d['items'])" "Jordan has 5+ notifications, 2+ unread, contract shape"
  check "{'request_received', 'request_accepted', 'new_message'} <= {n['type'] for n in d['items']} and all(n['request_id'] and n['listing_id'] for n in d['items'] if n['type'] != 'badge_earned')" "Jordan's notifications cover requests, an accept and a message, with IDs"
  check "[(n['created_at'], n['id']) for n in d['items']] == sorted(((n['created_at'], n['id']) for n in d['items']), reverse=True)" "Jordan's notifications newest first"
  check "any(n['type'] == 'new_message' and n['title'].startswith('Sam sent you') for n in d['items'])" "Jordan has a message notification from Sam"
  check "any(n['type'] == 'badge_earned' and n['title'] == 'You earned First Swap' and n['request_id'] is None and n['listing_id'] is None for n in d['items'])" "Jordan's history has a First Swap badge notification"
  bdg "$DEMO_J"
  bcheck "B['first_swap']['progress'] == 1 and ISO.match(B['first_swap']['earned_at'])" "Jordan's /me/badges: First Swap earned"
  bcheck "any(b['earned_at'] is None and 0 < b['progress'] < b['goal'] for b in B.values())" "Jordan has a badge in progress (e.g. Closet Cleanout)"

  req GET "/me/requests?role=incoming" "" "$DEMO_S"
  check "d['total'] >= 1" "Sam has incoming requests"
  req GET "/me/requests?role=outgoing" "" "$DEMO_S"
  check "any(r['owner']['name'] == 'Jordan Park' for r in d['items'])" "Sam has a request with Jordan"
  DEMO_RID="$(jget "next(r['id'] for r in d['items'] if r['owner']['name'] == 'Jordan Park')")"
  req GET "/requests/$DEMO_RID" "" "$DEMO_J"
  expect 200 "Jordan can open the Jordan-Sam request"
  req GET "/me/listings?status=completed" "" "$DEMO_R"
  expect 200 "Riley's completed listings"
  req GET /impact/me "" "$DEMO_J"
  expect 200 "Jordan's /impact/me"
  check "d['items_shared'] + d['items_received'] > 0 and d['textile_kg'] > 0 and d['water_l'] > 0 and d['co2_kg'] > 0" "Jordan's impact totals are > 0"
  req GET /me/saved "" "$DEMO_J"
  expect 200 "Jordan's /me/saved"
  check "d['total'] >= 2 and all(l['saved_by_me'] and not l['is_mine'] and l['status'] != 'hidden' for l in d['items'])" "Jordan has 2+ saved items, all flagged saved"
  DEMO_SAVED="$(jget "d['items'][0]['id']")"
  req GET "/listings/$DEMO_SAVED" "" "$DEMO_J"
  check "d['saved_by_me'] is True" "Jordan's saved item shows saved_by_me on detail"
  req GET "/listings/$DEMO_SAVED" "" "$DEMO_S"
  check "d['id'] == $DEMO_SAVED and isinstance(d['saved_by_me'], bool)" "Sam sees the same item with his own saved flag"
  req GET "/listings/$DEMO_SAVED/similar" "" "$DEMO_J"
  expect 200 "similar items for Jordan's saved item"
  check "len(d['items']) >= 3 and all(l['status'] == 'active' and not l['is_mine'] and l['id'] != $DEMO_SAVED for l in d['items'])" "demo item has 3+ similar items, active and not Jordan's"
  req GET "/listings?limit=50" "" "$DEMO_S"
  DEMO_ACTIVE="$(jget "' '.join(str(l['id']) for l in d['items'])")"
  n=0; slowest=0
  for lid in $DEMO_ACTIVE; do
    req POST "/listings/$lid/style" "" "$DEMO_S"
    [[ "$STATUS" == 200 ]] || fail "style demo listing $lid"
    check "$STYLE_SHAPE" "demo listing $lid has style ideas" >/dev/null
    faster_than 1 || fail "style demo listing $lid took ${SECS}s (not pre-warmed? run seed.style_warm + reseed)"
    slowest="$(python3 -c 'import sys; print(max(float(sys.argv[1]), float(sys.argv[2])))' "$slowest" "$SECS")"
    n=$((n + 1))
  done
  [[ $n -ge 20 ]] || fail "only $n demo listings styled"
  ok "all $n active demo listings return cached style ideas (slowest ${slowest}s)"
  req GET /impact/campus "" "$DEMO_J"
  expect 200 "Vanderbilt /impact/campus"
  check "d['items_rehomed'] > 0 and d['textile_kg'] > 0 and d['water_l'] > 0 and d['co2_kg'] > 0 and isinstance(d['top_dorm'], str)" "campus impact this week is > 0 with a top dorm"
  DEMO_TOP="$(jget "d['top_dorm']")"
  req GET /leaderboard/dorms "" "$DEMO_J"
  expect 200 "Vanderbilt /leaderboard/dorms"
  check "$BOARD_OK and len(d['items']) >= 3" "demo board has 3+ dorms, ranks consistent"
  check "d['items'][0]['dorm'] == '$DEMO_TOP' and d['items'][0]['rank'] == 1" "board's first dorm is /impact/campus top_dorm"
  DEMO_LB_DORMS="$(jget "sorted(r['dorm'] for r in d['items'])")"
  req GET /dorms "" "$DEMO_J"
  check "set($DEMO_LB_DORMS) <= set(d['items'])" "every board dorm is a Vanderbilt dorm"
  req GET "/requests/$DEMO_RID" "" "$DEMO_R"
  expect 403 forbidden "Riley can't open the Jordan-Sam request"
  req GET "/listings/$DEMO_LID" "" "$TOKEN_A"
  expect 404 not_found "smoke.edu user can't see a Vanderbilt listing"
  req GET "/listings?limit=50" "" "$TOKEN_A"
  check "not ({l['owner']['id'] for l in d['items']} & set($DEMO_OWNERS))" "smoke.edu feed has no Vanderbilt owners"
fi

# ---------------------------------------------------------------------------
echo
echo "PASS: $PASS checks against $BASE_URL"
