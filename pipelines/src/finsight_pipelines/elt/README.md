# Day 5 ELT boundary — reserved, not implemented

The future ELT loader will ingest immutable source-shaped records into PostgreSQL
`raw` tables before business transformation. It must not reuse the ETL's transformed
Parquet or curated records as its raw input. Add ingestion metadata, source identity
and necessary storage typing only. SQL/dbt will own transformation into reporting marts.

Day 1 implements only `finsight_pipelines.etl`. Do not add dbt execution here yet.
