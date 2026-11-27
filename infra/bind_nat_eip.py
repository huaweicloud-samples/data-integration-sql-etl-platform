import hashlib, hmac, datetime, urllib.request, urllib.error, urllib.parse, json, os, sys

AK = os.environ["HW_ACCESS_KEY"]
SK = os.environ["HW_SECRET_KEY"]
PROJECT_ID = os.environ.get("HW_PROJECT_ID", "cc2cb3d01b0c46798d77c4cd8ecf6b7e")
REGION = os.environ.get("HW_REGION", "cn-north-4")
ENDPOINT = f"vpc.{REGION}.myhuaweicloud.com"
NAT_ID = os.environ["NAT_GATEWAY_ID"]
EIP_ID = os.environ["NAT_EIP_ID"]
NAT_IP = os.environ["NAT_PORT_IP"]

def sign(method, path, query=None, body=b""):
    t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    cu = path if path.endswith("/") else path + "/"
    q = query or {}
    enc = lambda s: urllib.parse.quote(str(s), safe="-_.~")
    cq = "&".join(f"{enc(k)}={enc(v)}" for k, v in sorted(q.items()))
    h = {"host": ENDPOINT, "x-sdk-date": t, "x-project-id": PROJECT_ID}
    signed = sorted(h.keys())
    ch = "".join(f"{k}:{h[k]}\n" for k in signed)
    sh = ";".join(signed)
    cr = f"{method}\n{cu}\n{cq}\n{ch}\n{sh}\n{hashlib.sha256(body).hexdigest()}"
    sts = f"SDK-HMAC-SHA256\n{t}\n{hashlib.sha256(cr.encode()).hexdigest()}"
    sig = hmac.new(SK.encode(), sts.encode(), hashlib.sha256).hexdigest()
    return {**{k: h[k] for k in signed}, "Authorization": f"SDK-HMAC-SHA256 Access={AK}, SignedHeaders={sh}, Signature={sig}"}

def do(method, path, query=None, body=None):
    b = json.dumps(body).encode() if body is not None else b""
    hdrs = sign(method, path, query, b)
    qs = ("?" + urllib.parse.urlencode(query)) if query else ""
    url = f"https://{ENDPOINT}{path}{qs}"
    req = urllib.request.Request(url, data=b if b else None, headers=hdrs, method=method)
    try:
        r = urllib.request.urlopen(req, timeout=30)
        return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

# 1) find port id for the NAT gateway private IP
st, data = do("GET", f"/v1/{PROJECT_ID}/ports", query={"fixed_ips": f"ip_address={NAT_IP}"})
ports = json.loads(data).get("ports", []) if st == 200 else []
PORT_ID = ports[0]["id"] if ports else None
if not PORT_ID:
    print("ERROR: no port found for", NAT_IP); sys.exit(1)

# 2) bind EIP to that port (idempotent: re-PUT is harmless if already bound)
st2, data2 = do("PUT", f"/v1/{PROJECT_ID}/publicips/{EIP_ID}", body={"publicip": {"port_id": PORT_ID}})
print("BIND", st2, data2[:160])
print("DONE port_id=", PORT_ID)
