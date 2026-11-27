import os, sys, subprocess, json, hashlib, hmac, datetime, urllib.request, urllib.error, urllib.parse

AK  = os.environ["HW_ACCESS_KEY"]
SK  = os.environ["HW_SECRET_KEY"]
PID = os.environ.get("HW_PROJECT_ID", "cc2cb3d01b0c46798d77c4cd8ecf6b7e")
REGION = os.environ.get("HW_REGION", "cn-north-4")
NAT_ID = os.environ.get("NAT_ID", "af49efad-028e-44dd-b620-e7b7774131eb")

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
    auth = f"SDK-HMAC-SHA256 Access={AK}, SignedHeaders={sh}, Signature={sig}"
    return {**{k: h[k] for k in signed}, "Authorization": auth}

def do(host, method, path, query=None, body=None):
    b = json.dumps(body).encode() if body is not None else b""
    hdrs = sign(host, method, path, query, b)
    qs = ("?" + urllib.parse.urlencode(query)) if query else ""
    url = f"https://{host}{path}{qs}"
    req = urllib.request.Request(url, data=b if b else None, headers=hdrs, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

print("==== [1] Empty OBS buckets ====")
# 使用华为云 OBS 命令行工具 obsutil 清空桶（凭据由环境变量 HW_ACCESS_KEY / HW_SECRET_KEY 提供）
for b in ["spark-etl-datalake", "spark-etl-app-code"]:
    try:
        r = subprocess.run(["obsutil", "rm", f"obs://{b}", "-r", "-f"],
                           capture_output=True, text=True, timeout=300)
        print(f"  {b}: rc={r.returncode} {(r.stdout or r.stderr)[:140]}")
    except Exception as e:
        print(f"  {b}: ERROR {e}")

print("==== [2] Delete NAT SNAT rules ====")
nat_host = f"nat.{REGION}.myhuaweicloud.com"
for ver in ["v2.0", "v2"]:
    st, data = do(nat_host, "GET", f"/{ver}/{PID}/snat_rules", {"nat_gateway_id": NAT_ID})
    print(f"  GET /{ver}/snat_rules -> {st}")
    if st == 200:
        rules = json.loads(data).get("snat_rules", [])
        print(f"    found {len(rules)} SNAT rules")
        for r in rules:
            rid = r["id"]
            st2, d2 = do(nat_host, "DELETE", f"/{ver}/{PID}/snat_rules/{rid}")
            print(f"    DELETE rule {rid} -> {st2} {d2[:80]}")
        break
# attempt NAT gateway deletion directly too
st, d = do(nat_host, "DELETE", f"/v2/{PID}/nat_gateways/{NAT_ID}")
print(f"  DELETE nat_gateway {NAT_ID} -> {st} {d[:120]}")

print("==== [3] Delete SWR repo spark/arc ====")
swr_host = f"swr-api.{REGION}.myhuaweicloud.com"
st, d = do(swr_host, "DELETE", f"/v2/manage/namespaces/sparketl/repos/arc")
print(f"  DELETE repo arc -> {st} {d[:160]}")
st2, d2 = do(swr_host, "DELETE", f"/v2/manage/namespaces/sparketl")
print(f"  DELETE namespace spark -> {st2} {d2[:160]}")

print("DONE")
