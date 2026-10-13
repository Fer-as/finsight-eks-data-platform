# Local data artifacts

The generator writes `raw/*.csv`. The ETL writes `curated/<source-hash>/*.parquet`
and `rejected/<source-hash>/*.json`. These generated directories are ignored by Git.
The hash covers all four source files and the dataset/rule configuration.
PostgreSQL is loaded from the written Parquet files.

All account references are invented `SYN-xxxx` identifiers. Never put customer data here.
