"""Read-only check of the live server against the app's Codable models.
Logs in as the three demo accounts, GETs every read endpoint, and reports server keys the app is missing or
nulls where a model is non-optional. Never creates, edits or deletes data, and skips GET /requests/{id}/messages
(it moves read markers). Usage: python3 -I ios/Tools/live-audit.py
"""
import json, os, re, sys, urllib.request
B="http://163.192.218.131:8000"
src=open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Loop", "Models", "Models.swift")).read()
structs={}
for m in re.finditer(r"struct (\w+):[^{]*\{(.*?)\n\}", src, re.S):
    props=[]
    for p in re.finditer(r"^\s+(?:let|var) (\w+): ([\w\[\]]+)(\?)?\s*$", m.group(2), re.M):
        props.append((p.group(1),p.group(2),bool(p.group(3))))
    structs[m.group(1)]=props
snake=lambda s: re.sub(r"([A-Z])",lambda m:"_"+m.group(1).lower(),s)
issues=[]; extras=set()
def check(obj,model,path):
    if model not in structs: return
    if not isinstance(obj,dict): issues.append(f"{path}: expected object for {model}, got {type(obj).__name__}"); return
    mk={snake(n):(t,o) for n,t,o in structs[model]}
    for k,(t,o) in mk.items():
        if k not in obj: 
            if not o and not t.startswith("["): issues.append(f"{path}: server omits required '{k}' ({model})")
            continue
        v=obj[k]
        if v is None and not o: issues.append(f"{path}.{k}: null but {model}.{k} is non-optional")
        base=t.strip("[]")
        if isinstance(v,list):
            for i,x in enumerate(v[:50]): check(x,base,f"{path}.{k}[{i}]")
        elif isinstance(v,dict): check(v,base,f"{path}.{k}")
    for k in obj:
        if k not in mk: extras.add(f"{model}.{k}")
def call(path,tok=None,method="GET",body=None):
    r=urllib.request.Request(B+path,method=method,headers={"Content-Type":"application/json",**({"Authorization":"Bearer "+tok} if tok else {})},data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(r,timeout=20) as f: return f.status,json.loads(f.read() or b"null")
    except urllib.error.HTTPError as e: return e.code,None
for email in ["jordan.park","sam.lee","riley.chen"]:
    st,login=call("/auth/login",method="POST",body={"email":email+"@vanderbilt.edu"})
    assert st==200,(email,st); tok=login["token"]
    check(login["user"],"User",email+" login.user")
    eps=[("/me","User"),("/me/unread","Unread"),("/impact/me","MyImpact"),("/impact/campus","CampusImpact"),("/me/saved?limit=50","Listing*"),("/me/badges","Badge*"),("/notifications?limit=20","AppNotification*"),("/leaderboard/dorms","LeaderboardEntry*"),("/meetup-spots","MeetupSpot*"),("/listings?limit=50","Listing*"),("/me/listings?status=active","Listing*"),("/me/listings?status=completed","Listing*"),("/me/requests?role=incoming","ExchangeRequest*"),("/me/requests?role=outgoing","ExchangeRequest*")]
    for p,m in eps:
        st,d=call(p,tok)
        if st!=200: issues.append(f"{email} GET {p} -> {st}"); continue
        if m.endswith("*"):
            for i,x in enumerate(d["items"]): check(x,m[:-1],f"{email} {p}[{i}]")
            print(email,p,len(d["items"]),"items")
        else: check(d,m,f"{email} {p}")
    if email=="jordan.park":
        st,d=call("/listings?limit=50",tok); lid=d["items"][0]["id"]
        for p,m in [(f"/listings/{lid}","Listing"),(f"/listings/{lid}/similar","Listing*")]:
            st,d2=call(p,tok); 
            if m.endswith("*"): [check(x,"Listing",p) for x in d2["items"]]
            else: check(d2,m,p)
        st,d=call("/me/requests?role=incoming",tok)
        if d["items"]:
            st,r=call(f"/requests/{d['items'][0]['id']}",tok); check(r,"ExchangeRequest","/requests/{id}")
        for p in ["/events","/donation-bins","/dorms"]:
            st,d=call(p,tok); print(p,st,len(d["items"]) if d else None)
print("\nISSUES:",*issues or ["none"],sep="\n  ")
print("\nSERVER KEYS THE APP IGNORES:",*sorted(extras),sep="\n  ")
