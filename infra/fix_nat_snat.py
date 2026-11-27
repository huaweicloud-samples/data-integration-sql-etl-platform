"""为 NAT 网关创建 SNAT 规则（华为云正确做法）：
1) 解绑 EIP（若已手动绑到 NAT 端口）
2) 查找节点子网 network_id
3) POST /v2/{project}/snat_rules 创建 SNAT 规则（自动关联 EIP）
幂等：SNAT 规则已存在时跳过。
"""
import hashlib, hmac, datetime, urllib.request, urllib.error, urllib.parse, json, os, sys, time

AK = os.environ.get("HW_ACCESS_KEY", "")
SK = os.environ.get("HW_SECRET_KEY", "")
PROJECT_ID = os.environ.get("HW_PROJECT_ID", "cc2cb3d01b0c46798d77c4cd8ecf6b7e")
REGION = os.environ.get("HW_REGION", "cn-north-4")
NAT_ID = os.environ["NAT_GATEWAY_ID"]
EIP_ID = os.environ["NAT_EIP_ID"]
VPC_EP = f"vpc.{REGION}.myhuaweicloud.com"
NAT_EP = f"nat.{REGION}.myhuaweicloud.com"

def sign(endpoint, method, path, query=None, body=b""):
    t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    cu = path if path.endswith("/") else path + "/"
    q = query or {}
    enc = lambda s: urllib.parse.quote(str(s), safe="-_.~")
    cq = "&".join(f"{enc(k)}={enc(v)}" for k, v in sorted(q.items()))
    h = {"host": endpoint, "x-sdk-date": t, "x-project-id": PROJECT_ID}
    signed = sorted(h.keys())
    ch = "".join(f"{k}:{h[k]}\n" for k in signed)
    sh = ";".join(signed)
    cr = f"{method}\n{cu}\n{cq}\n{ch}\n{sh}\n{hashlib.sha256(body).hexdigest()}"
    sts = f"SDK-HMAC-SHA256\n{t}\n{hashlib.sha256(cr.encode()).hexdigest()}"
    sig = hmac.new(SK.encode(), sts.encode(), hashlib.sha256).hexdigest()
    return {**{k: h[k] for k in signed}, "Authorization": f"SDK-HMAC-SHA256 Access={AK}, SignedHeaders={sh}, Signature={sig}"}

def do(endpoint, method, path, query=None, body=None):
    b = json.dumps(body).encode() if body is not None else b""
    hdrs = sign(endpoint, method, path, query, b)
    if body is not None:
        hdrs["Content-Type"] = "application/json"
    qs = ("?" + urllib.parse.urlencode(query)) if query else ""
    url = f"https://{endpoint}{path}{qs}"
    req = urllib.request.Request(url, data=b if b else None, headers=hdrs, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

# 0) 已有 SNAT 规则则直接退出（幂等）
st, data = do(NAT_EP, "GET", f"/v2/{PROJECT_ID}/snat_rules", query={"nat_gateway_id": NAT_ID})
if st == 200:
    rules = json.loads(data).get("snat_rules", [])
    if rules:
        print("SNAT rule already exists:", [(r["id"], r.get("status")) for r in rules])
        sys.exit(0)
else:
    print("WARN list snat_rules:", st, data[:200])

# 1) 解绑 EIP（若已绑定）
st, data = do(VPC_EP, "GET", f"/v1/{PROJECT_ID}/publicips/{EIP_ID}")
eip = json.loads(data).get("publicip", {}) if st == 200 else {}
print("EIP status:", eip.get("status"), "port:", eip.get("port_id"))
if eip.get("port_id"):
    st, data = do(VPC_EP, "PUT", f"/v1/{PROJECT_ID}/publicips/{EIP_ID}", body={"publicip": {"port_id": ""}})
    print("UNBIND", st, data[:160])
    time.sleep(5)

# 2) 找节点子网（10.0.1.0/24 及其它 10.0.x）的 network id
st, data = do(VPC_EP, "GET", f"/v1/{PROJECT_ID}/subnets")
subnets = json.loads(data).get("subnets", []) if st == 200 else []
targets = [s for s in subnets if s.get("cidr", "").startswith("10.0.")]
if not targets:
    print("ERROR: no target subnets found"); sys.exit(1)

# 3) 为每个子网创建 SNAT 规则（共用同一个 EIP）
ok = False
for s in targets:
    net_id = s.get("neutron_network_id") or s["id"]
    st, data = do(NAT_EP, "POST", f"/v2/{PROJECT_ID}/snat_rules",
                  body={"snat_rule": {"nat_gateway_id": NAT_ID, "network_id": net_id, "floating_ip_id": EIP_ID}})
    print(f"SNAT create for {s.get('cidr')} ({net_id}):", st, data[:200])
    if st in (200, 201):
        ok = True

# 4) 等待规则 ACTIVE
for _ in range(12):
    st, data = do(NAT_EP, "GET", f"/v2/{PROJECT_ID}/snat_rules", query={"nat_gateway_id": NAT_ID})
    rules = json.loads(data).get("snat_rules", []) if st == 200 else []
    if rules and all(r.get("status") == "ACTIVE" for r in rules):
        print("ALL ACTIVE:", [(r["id"], r["status"]) for r in rules]); sys.exit(0)
    print("waiting...", [(r.get("id"), r.get("status")) for r in rules])
    time.sleep(10)
sys.exit(0 if ok else 1)
