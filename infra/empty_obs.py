import os, subprocess

REGION = os.environ.get("HW_REGION", "cn-north-4")
# 使用华为云 OBS 命令行工具 obsutil 清空并删除桶（凭据由环境变量 HW_ACCESS_KEY / HW_SECRET_KEY 提供）
for b in ["spark-etl-datalake", "spark-etl-app-code"]:
    try:
        r = subprocess.run(["obsutil", "rm", f"obs://{b}", "-r", "-f"],
                           capture_output=True, text=True, timeout=300)
        print(f"{b}: rc={r.returncode} {(r.stdout or r.stderr)[:160]}")
    except Exception as e:
        print(f"{b}: ERROR {type(e).__name__} {str(e)[:120]}")
print("DONE")
