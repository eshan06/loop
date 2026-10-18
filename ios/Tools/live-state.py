"""Read-only snapshot of Jordan's and Sam's live state (listings, requests, notifications, impact, badges).
Skips GET /requests/{id}/messages (it moves read markers). Usage: python3 -I ios/Tools/live-state.py"""
import json, urllib.request
B = "http://163.192.218.131:8000"
def call(p, tok=None, method="GET", body=None):
    r = urllib.request.Request(B + p, method=method, headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})}, data=json.dumps(body).encode() if body is not None else None)
    with urllib.request.urlopen(r, timeout=20) as f: return json.loads(f.read())
for who in ["jordan.park", "sam.lee"]:
    t = call("/auth/login", method="POST", body={"email": who + "@vanderbilt.edu"})["token"]
    print("=====", who)
    print("unread", call("/me/unread", t))
    print("impact", call("/impact/me", t))
    print("badges", [(b["id"], f'{b["progress"]}/{b["goal"]}', b["earned_at"]) for b in call("/me/badges", t)["items"]])
    for l in call("/me/listings?status=active&limit=3", t)["items"][:2]:
        print("my listing", l["id"], l["title"], l["status"], l["category"], l["size"], l["brand"], l["condition"], "|", l.get("condition_note"), "| photos", [p["kind"] for p in l["photos"]], "| pending", l["pending_request_count"])
    for role in ["incoming", "outgoing"]:
        for r in call(f"/me/requests?role={role}", t)["items"][:4]:
            print(role, r["id"], r["listing"]["title"], r["listing"]["status"], "req:", r["status"], "unread", r["unread_messages"], r["requester"]["name"], "->", r["owner"]["name"])
    for n in call("/notifications?limit=5", t)["items"][:5]:
        print("note", n["type"], "|", n["title"], "|", n["body"], "| read", n["read"])
if True:
    print("campus", call("/impact/campus", t)); print("board", [(x["rank"], x["dorm"], x["items_shared"]) for x in call("/leaderboard/dorms", t)["items"][:3]])
