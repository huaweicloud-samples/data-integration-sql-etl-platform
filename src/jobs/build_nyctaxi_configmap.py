#!/usr/bin/env python3
# ============================================================================
# 由源文件重建 nyctaxi-config ConfigMap（notebook + schema）。
# 仅在需要重新生成 src/manifests/nyctaxi-config.yaml 时运行；
# 日常部署直接用已提交的预生成清单即可（kubectl apply -f nyctaxi-config.yaml）。
#
# 用法:
#   python3 build_nyctaxi_configmap.py \
#       --notebook src/notebooks/nyctaxi.ipynb \
#       --schema   src/notebooks/green_tripdata0.json \
#       --out      src/manifests/nyctaxi-config.yaml
# ============================================================================
import argparse, base64, json, os

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--notebook", required=True)
    ap.add_argument("--schema", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default="nyctaxi-config")
    ap.add_argument("--namespace", default="spark")
    a = ap.parse_args()

    with open(a.notebook, "rb") as f:
        nb = f.read()
    with open(a.schema, "rb") as f:
        schema = f.read()

    cm = {
        "apiVersion": "v1",
        "kind": "ConfigMap",
        "metadata": {"name": a.name, "namespace": a.namespace},
        "binaryData": {
            "nyctaxi.ipynb": base64.b64encode(nb).decode("ascii"),
            "green_tripdata0.json": base64.b64encode(schema).decode("ascii"),
        },
    }
    out_dir = os.path.dirname(a.out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(cm, f, indent=2)
    print(f"wrote {a.out} (notebook {len(nb)}B, schema {len(schema)}B)")

if __name__ == "__main__":
    main()
