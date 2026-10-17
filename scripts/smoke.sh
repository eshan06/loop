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
echo
echo "PASS: $PASS checks against $BASE_URL"
