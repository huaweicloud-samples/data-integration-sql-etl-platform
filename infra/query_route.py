import os, hashlib, hmac, datetime, urllib.request, json

AK = os.environ["HW_ACCESS_KEY"]
SK = os.environ["HW_SECRET_KEY"]
PROJECT_ID = os.environ["HW_PROJECT_ID"]
RTB_ID = "93878c46-856b-48d5-8984-d96cb966735c"
ENDPOINT = "vpc.cn-north-4.myhuaweicloud.com"
METHOD = "GET"
PATH = f"/v1/{PROJECT_ID}/routetables/{RTB_ID}"

def build_auth(method, path, query=b"", body=b""):
    t = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    canonical_uri = path if path.endswith("/") else path + "/"
    canonical_query = query.decode() if isinstance(query, bytes) else query
    h = {"host": ENDPOINT, "x-sdk-date": t, "x-project-id": PROJECT_ID}
    signed = sorted(h.keys())
    canonical_headers = "".join(f"{k}:{h[k]}\n" for k in signed)
    signed_headers = ";".join(signed)
    payload_hash = hashlib.sha256(body).hexdigest()
    canonical_request = f"{method}\n{canonical_uri}\n{canonical_query}\n{canonical_headers}\n{signed_headers}\n{payload_hash}"
    string_to_sign = f"SDK-HMAC-SHA256\n{t}\n{hashlib.sha256(canonical_request.encode()).hexdigest()}"
    signature = hmac.new(SK.encode(), string_to_sign.encode(), hashlib.sha256).hexdigest()
    auth = f"SDK-HMAC-SHA256 Access={AK}, SignedHeaders={signed_headers}, Signature={signature}"
    return auth, {k.capitalize() if k!="x-sdk-date" and k!="x-project-id" else k: v for k,v in h.items()}

auth, headers = build_auth(METHOD, PATH)
url = f"https://{ENDPOINT}{PATH}"
req = urllib.request.Request(url, headers={**headers, "Authorization": auth}, method=METHOD)
try:
    resp = urllib.request.urlopen(req, timeout=30)
    print("HTTP", resp.status)
    data = json.loads(resp.read().decode())
    rt = data.get("routetable", data)
    print("name:", rt.get("name"), "default:", rt.get("default"))
    for r in rt.get("routes", []):
        print("ROUTE:", r)
except urllib.error.HTTPError as e:
    print("HTTPError", e.code, e.read().decode())
