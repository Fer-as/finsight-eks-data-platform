# Local data artifacts

The generator writes `raw/*.csv`. The ETL writes `curated/<source-hash>/*.parquet`
and `rejected/<source-hash>/*.json`. These generated directories are ignored by Git.
The hash covers all four source files and the dataset/rule configuration.
PostgreSQL is loaded from the written Parquet files.

All account references are invented `SYN-xxxx` identifiers. Never put customer data here.

## Data statement

All data in FinSight, locally and in the deployed environment, is synthetic:
- It is produced by [`synthetic.py`](../pipelines/src/finsight_pipelines/synthetic.py) from the
  parameters in [`config/synthetic.json`](../config/synthetic.json). The generator uses a fixed seed
  (42) and year (2025), and no wall-clock time, external data source or third-party data library.
- The three departments are generic names (Retail Banking, Commercial Banking, Operations), and
  account references are invented `SYN-0000` to `SYN-0199` identifiers.
- The dataset has no names, addresses, email addresses, card or account numbers, or any other
  personal data fields.
- No dataset is committed to Git or built into an image. The CSV and Parquet files are generated at
  run time, locally by Docker Compose and in the cluster by the `finsight-db-init` Job.
- The same seed and configuration reproduce identical data, checked in CI by
  `pipelines/tests/test_etl.py`.
