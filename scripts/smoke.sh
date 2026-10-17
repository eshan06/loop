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

LISTING_KEYS='{"id","title","category","size","color","brand","condition","description","tags","share_type","status","photos","meetup_spot","owner","impact","is_mine","saved_by_me","my_request_status","my_request_id","pending_request_count","accepted_request_id","created_at"}'

req POST /listings "{\"title\": \"  Smoke trucker jacket $MK \", \"category\": \"outerwear\", \"size\": \"M\", \"color\": \"Light wash blue\", \"brand\": \"Levis\", \"condition\": \"good\", \"description\": \"Classic trucker jacket.\", \"tags\": [\"denim\", \" jacket \", \"tagonly${RUN}\"], \"share_type\": \"swap\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P1, $P2, $P3]}" "$TOKEN_A"
expect 201 "POST /listings full body"
check "set(d) == $LISTING_KEYS" "Listing has exactly the contract keys"
check "d['title'] == 'Smoke trucker jacket $MK' and d['category'] == 'outerwear' and d['size'] == 'M' and d['brand'] == 'Levis' and d['condition'] == 'good' and d['share_type'] == 'swap'" "fields saved, title trimmed"
check "d['tags'] == ['denim', 'jacket', 'tagonly${RUN}']" "tags trimmed, in order"
check "d['status'] == 'active' and ISO.match(d['created_at'])" "starts active, created_at ISO Z"
check "[p['id'] for p in d['photos']] == [$P1, $P2, $P3] and [p['kind'] for p in d['photos']] == ['front', 'back', 'label']" "photos attached in order with kinds"
check "all(p['url'].startswith('$BASE_URL/media/') for p in d['photos'])" "photo urls absolute"
check "d['meetup_spot']['id'] == $SPOT1 and isinstance(d['meetup_spot']['name'], str)" "meetup_spot object"
check "d['owner'] == {'id': $USER_A, 'name': 'Smoke Tester', 'dorm': None, 'avatar_url': '$AVATAR_URL', 'items_shared': 0}" "owner is A as an Owner"
check "set(d['impact']) == {'textile_kg', 'water_l', 'co2_kg'} and all(isinstance(v, (int, float)) and v > 0 for v in d['impact'].values())" "impact numbers"
check "d['is_mine'] is True and d['saved_by_me'] is False and d['my_request_status'] is None and d['my_request_id'] is None" "is_mine true, no request, not saved"
check "d['pending_request_count'] == 0 and d['accepted_request_id'] is None" "owner counts empty"
L1="$(jget 'd["id"]')"

req POST /listings "{\"title\": \"Smoke tee $MK\", \"category\": \"TOPS\", \"size\": \"s\", \"condition\": \"like_new\", \"share_type\": \"free\", \"meetup_spot_id\": $SPOT1, \"photo_ids\": [$P4]}" "$TOKEN_A"
expect 201 "POST /listings required fields only"
check "d['color'] is None and d['brand'] is None and d['description'] is None and d['tags'] == []" "optional fields null, tags []"
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
check 'sorted(d["draft"]) == sorted(["title","category","size","color","brand","condition","description","tags"])' "draft has exactly the ScanDraft keys"
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
req POST "/requests/$RB/complete" "" "$TOKEN_B"
expect 200 "B (requester) completes the exchange"
check "d['status'] == 'completed' and d['listing']['status'] == 'completed' and d['owner']['items_shared'] == 1" "completed, listing completed, owner items_shared 1"
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
check "d['total'] == 6 and $RB in [x['id'] for x in d['items']][:2]" "6 incoming, the completed one at the top"
check "all(a['updated_at'] >= b['updated_at'] for a, b in zip(d['items'], d['items'][1:]))" "sorted by updated_at desc"
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
echo
echo "PASS: $PASS checks against $BASE_URL"
