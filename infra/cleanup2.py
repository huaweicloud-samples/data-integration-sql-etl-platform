import os, subprocess, hashlib, hmac, datetime, urllib.request, urllib.error, urllib.parse, json

AK = os.environ["HW_ACCESS_KEY"]
SK = os.environ["HW_SECRET_KEY"]
PID = os.environ.get("HW_PROJECT_ID", "cc2cb3d01b0c46798d77c4cd8ecf6b7e")
REGION = os.environ.get("HW_REGION", "cn-north-4")
NAT_ID = "af49efad-028e-44dd-b620-e7b7774131eb"

def sign(host, method, path, query=None, body=b""):
    t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    cu = path if path.endswith("/") else path + "/"
    q = query or {}
    enc = lambda s: urllib.parse.quote(str(s), safe="-_.~")
    cq = "&".join(f"{enc(k)}={enc(v)}" for k, v in sorted(q.items()))
    h = {"host": host, "x-sdk-date": t, "x-project-id": PID}
    signed = sorted(h.keys())
    ch = "".join(f"{k}:{h[k]}\n" for k in signed)
    sh = ";".join(signed)
    cr = f"{method}\n{cu}\n{cq}\n{ch}\n{sh}\n{hashlib.sha256(body).hexdigest()}"
    sts = f"SDK-HMAC-SHA256\n{t}\n{hashlib.sha256(cr.encode()).hexdigest()}"
    sig = hmac.new(SK.encode(), sts.encode(), hashlib.sha256).hexdigest()
    return {**{k: h[k] for k in signed}, "Authorization": f"SDK-HMAC-SHA256 Access={AK}, SignedHeaders={sh}, Signature={sig}"}

def do(host, method, path, query=None, body=None):
    b = json.dumps(body).encode() if body is not None else b""
    hdrs = sign(host, method, path, query, b)
    qs = ("?" + urllib.parse.urlencode(query)) if query else ""
    req = urllib.request.Request(f"https://{host}{path}{qs}", data=b if b else None, headers=hdrs, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

print("==== OBS bucket cleanup ====")
# 使用华为云 OBS 命令行工具 obsutil 删除桶（凭据由环境变量 HW_ACCESS_KEY / HW_SECRET_KEY 提供）
for b in ["spark-etl-datalake", "spark-etl-app-code"]:
    try:
        r = subprocess.run(["obsutil", "rm", f"obs://{b}", "-r", "-f"],
                           capture_output=True, text=True, timeout=120)
        print(f"  {b}: rc={r.returncode} {(r.stdout or r.stderr)[:140]}")
    except Exception as e:
        print(f"  {b}: {type(e).__name__} {str(e)[:140]}")

print("==== NAT v2.0 gateway delete attempt ====")
nh = f"nat.{REGION}.myhuaweicloud.com"
st, d = do(nh, "DELETE", f"/v2.0/{PID}/nat_gateways/{NAT_ID}")
print(f"  v2.0 nat_gw -> {st} {d[:140]}")

print("==== NAT v2.0 SNAT rule delete attempt ====")
rules = ["0b087e9d-ca23-41ad-b43c-ab2bdd2aa501", "bdc40dcb-181a-4a45-9975-1e649a2d8405"]
for rid in rules:
    st, d = do(nh, "DELETE", f"/v2.0/{PID}/snat_rules/{rid}")
    print(f"  v2.0 snat {rid[:8]} -> {st} {d[:90]}")

st2, _ = do(nh, "GET", f"/v2/{PID}/nat_gateways/{NAT_ID}")
print("NAT GW now ->", st2, "EXISTS" if st2 == 200 else "GONE")
print("DONE")
