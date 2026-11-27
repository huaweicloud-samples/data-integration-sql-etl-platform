"""
OBS Spark 适配器
==============================================

本模块在华为云 CCE 上为 Spark 作业提供 OBS（obs://）访问配置：
凭证由 CCE 委托（Agency）注入的环境变量 / 挂载的 CSMS 凭据提供。

`build_obs_spark_conf()` 生成注入到 `spark-submit --conf` 的 OBS 配置集合
（Hadoop-OBS filesystem），上层 notebook / SQL 可按需使用 obs:// 路径。

依赖：pyspark（运行在 Spark Driver 容器内）。华为云 OBS Hadoop connector jar 需预置在
Spark 的 classpath（见 deployment-guide 与 manifests）。
"""

import os
from typing import Dict


# s3a 路径前缀转 OBS 前缀
# 例：s3a://nyc-tlc/csv_backup  →  obs://nyc-tlc/csv_backup
def s3a_to_obs(path: str) -> str:
    """将 s3a://bucket/key 替换为 obs://bucket/key（保留桶名与对象键）。"""
    if path.startswith("s3a://") or path.startswith("s3://"):
        return "obs://" + path.split("://", 1)[1]
    return path


# 华为云 OBS Hadoop filesystem 必需配置键
OBS_CONF_KEYS = {
    "fs.obs.impl": "org.apache.hadoop.fs.obs.OBSFileSystem",
    "fs.obs.access.key": "HW_ACCESS_KEY",       # 由 CCE 委托注入环境变量
    "fs.obs.secret.key": "HW_SECRET_KEY",
    "fs.obs.endpoint": "obs.{region}.myhuaweicloud.com",
}


def build_obs_spark_conf(
    region: str = None,
    app_code_bucket: str = None,
    datalake_bucket: str = None,
    extra: Dict[str, str] = None,
) -> Dict[str, str]:
    """
    生成注入到 spark-submit --conf 的 OBS 配置集合。

    参数：
        region:            华为云区域，默认读 HW_REGION
        app_code_bucket:   代码桶
        datalake_bucket:   数据湖桶
        extra:             额外 spark conf（会覆盖同名默认项）
    返回：
        { "spark.hadoop.fs.obs.impl": "...", ... } 可直接转成 --conf 列表
    """
    region = region or os.environ.get("HW_REGION", "cn-north-4")

    conf = {
        "spark.hadoop.fs.obs.impl": OBS_CONF_KEYS["fs.obs.impl"],
        # 凭证优先取环境变量（CCE 委托签发），避免硬编码
        "spark.hadoop.fs.obs.access.key": os.environ.get("HW_ACCESS_KEY", ""),
        "spark.hadoop.fs.obs.secret.key": os.environ.get("HW_SECRET_KEY", ""),
        "spark.hadoop.fs.obs.endpoint": OBS_CONF_KEYS["fs.obs.endpoint"].format(region=region),
        # 通用 Spark 行为配置
        "spark.io.encryption.enabled": "true",
        "spark.network.crypto.enabled": "true",
        "spark.sql.ansi.enabled": "true",
        "spark.sql.adaptive.enabled": "true",
        # 让 obs:// 成为默认 fs 之一
        "spark.hadoop.fs.obs.connection.ssl.enabled": "true",
    }

    if app_code_bucket:
        conf["spark.hadoop.fs.obs.app.code.bucket"] = app_code_bucket
    if datalake_bucket:
        conf["spark.hadoop.fs.obs.datalake.bucket"] = datalake_bucket

    if extra:
        conf.update(extra)
    return conf


def conf_to_spark_args(conf: Dict[str, str]) -> list:
    """把 conf dict 转成 spark-submit 的 --conf k=v 列表。"""
    return [f"--conf {k}={v}" for k, v in conf.items()]


# ---------------------------------------------------------------------------
# 用法示例
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    # 示例数据源
    src = "s3a://nyc-tlc/csv_backup/green_tripdata*.csv"
    dst = "s3a://my-datalake/green_taxi/"

    print("# 路径翻译（上层 notebook/SQL 仅需这一步）")
    print("source :", s3a_to_obs(src))
    print("dest   :", s3a_to_obs(dst))

    print("\n# 注入 spark-submit 的 OBS 配置")
    c = build_obs_spark_conf(
        app_code_bucket="spark-etl-app-code",
        datalake_bucket="spark-etl-datalake",
    )
    for arg in conf_to_spark_args(c):
        print(arg)
