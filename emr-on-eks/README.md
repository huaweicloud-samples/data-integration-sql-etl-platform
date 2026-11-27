<!--
SPDX-FileCopyrightText: 2021 本开源样例贡献者.

SPDX-License-Identifier: MIT-0
-->

# Arc ETL framework on EMR on CCE
This sample demonstrates an end-to-end process to provision a CCE cluster and execute a Spark ETL job defined as a [jupyter notebook](green_taxi_load.ipynb) using [Arc Framework](https://arc.tripl.ai/getting-started/).

# Provisioning
1. Set `HW_REGION` to your target region (e.g. `cn-north-4`).
2. Run the following command to provision a new CCE cluster `eks-cluster` backed by Fargate and build a virtual EMR cluster `emr-on-eks-cluster`
```bash
bash emr-on-eks/provision.sh
```
3. Once provisioning is complete (~20 min), run the following command to submit a new Spark job on the virtual EMR cluster:
```bash
bash emr-on-eks/submit_arc_job.sh
```
The sample job will create an output OBS bucket, load the [TLC green taxi trip records](https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page) from public `obs://nyc-tlc/csv_backup/green_tripdata*.csv`, apply schema, convert it into Parquet and store it in the output OBS bucket.

The job is defined as a [jupyter notebook green_taxi_load.ipynb](green_taxi_load.ipynb) using [Arc Framework](https://arc.tripl.ai/getting-started/) and the applied schema is defined in [green_taxi_schema.json](green_taxi_schema.json)


## Huawei Cloud Resources
* CCE cluster: view it in the CCE console
* Virtual EMR clusters and jobs: view them in the MRS console
* EMR job logs: view them in the LTS console
* OBS buckets: view the output bucket in the OBS console

## CCE Resources
To review the execution process, run:
```
kubectl get po -n emr
```

# Cleanup
To clean up resources, run:
```bash
bash emr-on-eks/deprovision.sh
```



That's it!
