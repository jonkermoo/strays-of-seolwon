"""Style-test asset upload (M1 test scene only, never production).

Uploads images (as Decals) or models (FBX) to the owner of ROBLOX_API_KEY through Open Cloud,
sequentially, and records name -> asset id in a JSON map so reruns skip what is done.
The key is read from the environment and never printed.

python tools/styletest/upload.py <map.json> <user id> <file> [<file> ...]
  image files (.png) upload as Decal; .fbx as Model. Decal ids must be resolved to image ids
  once in Studio (InsertService:LoadAsset(decalId).Decal.Texture), see notes/traps/assets.md.
"""
import json, os, sys, time, uuid, urllib.request, urllib.error

BASE = "https://apis.roblox.com/assets/v1"
KEY = os.environ["ROBLOX_API_KEY"]
CT = {".png": ("Decal", "image/png"), ".fbx": ("Model", "model/fbx")}


def call(req):
    for i in range(6):
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as e:
            msg = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503):
                time.sleep(5 * (i + 1)); continue
            raise SystemExit(f"HTTP {e.code}: {msg}")
    raise SystemExit("gave up after retries")


def upload(path, user):
    ext = os.path.splitext(path)[1].lower(); atype, ctype = CT[ext]
    name = "SOS styletest " + os.path.basename(path)[:40]
    req_json = {"assetType": atype, "displayName": name, "description": "Strays of Seolwon M1 style test (private test asset)",
                "creationContext": {"creator": {"userId": str(user)}}}
    b = uuid.uuid4().hex; body = bytearray()
    body += f"--{b}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n{json.dumps(req_json)}\r\n".encode()
    body += f"--{b}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{os.path.basename(path)}\"\r\nContent-Type: {ctype}\r\n\r\n".encode()
    body += open(path, "rb").read() + f"\r\n--{b}--\r\n".encode()
    r = urllib.request.Request(f"{BASE}/assets", data=bytes(body), method="POST")
    r.add_header("x-api-key", KEY); r.add_header("Content-Type", f"multipart/form-data; boundary={b}")
    op = call(r)["path"]
    for _ in range(80):
        p = urllib.request.Request(f"{BASE}/{op}"); p.add_header("x-api-key", KEY)
        st = call(p)
        if st.get("done"):
            resp = st.get("response", {})
            return resp.get("assetId"), resp.get("moderationResult", {}).get("moderationState")
        time.sleep(3)
    return None, "timeout"


mp, user, files = sys.argv[1], sys.argv[2], sys.argv[3:]
M = json.load(open(mp)) if os.path.exists(mp) else {}
for f in files:
    k = os.path.basename(f)
    if k in M and M[k].get("id"): continue
    aid, state = upload(f, user)
    M[k] = {"id": aid, "state": state}
    json.dump(M, open(mp, "w"), indent=1)
    print(k, aid, state, flush=True)
print("done", len(M))
