# KPI spot-check against SQL (F8), 20 October 2026

I compared the dashboard figures served by the live API with totals computed by plain SQL. The
check used no AWS access.

## Method

1. **Dashboard figures.** A public HTTPS request on 20 October 2026 (07:41 UTC):
   `GET https://eks.feras-dev.co.uk/api/dashboard?start=2025-01-01&end=2026-01-01`. The same figures
   were returned on 17 October 2026.
2. **SQL totals.** I re-ran the deterministic generator,
   `pipelines/src/finsight_pipelines/synthetic.py`, with `config/synthetic.json` (seed 42, year 2025).
   The cluster's `finsight-db-init` Job loads data from the same generator and configuration. I loaded
   the generated CSV files into an in-memory SQLite database and computed each total with the SQL
   below, following [the KPI definitions](../kpi-definitions.md).

```sql
-- Revenue and expenses (pence), reporting window [2025-01-01, 2026-01-01)
select sum(amount_pence) from entries
 where kind = 'revenue' and booked_on >= '2025-01-01' and booked_on < '2026-01-01';
select sum(amount_pence) from entries
 where kind = 'expense' and booked_on >= '2025-01-01' and booked_on < '2026-01-01';
-- Expense budget (pence)
select sum(amount_pence) from budgets where month >= '2025-01-01' and month < '2026-01-01';
-- Transaction volume, flagged (medium or high) and high (both rules); timestamps are UTC
select count(*), sum(amount_pence) from transactions;
select count(*) from transactions
 where amount_pence >= 1000000 or cast(substr(occurred_at, 12, 2) as integer) < 6;
select count(*) from transactions
 where amount_pence >= 1000000 and cast(substr(occurred_at, 12, 2) as integer) < 6;
```

## Result

| KPI | SQL | Dashboard API | Match |
|---|---:|---:|---|
| Revenue | £3,501,600.00 | 3501600.00 | Yes |
| Expenses | £2,392,450.00 | 2392450.00 | Yes |
| Operating profit (revenue − expenses) | £1,109,150.00 | 1109150.00 | Yes |
| Profit margin | 31.6755%, 31.68 after round-half-up | 31.68 | Yes |
| Expense budget | £2,400,000.00 | 2400000.00 | Yes |
| Transaction volume | £51,374,221.39 | 51374221.39 | Yes |
| Flagged transactions | 2,628 of 10,000 (26.28%) | 2628, 26.28 | Yes |
| High (both rules) | 104 | 104 | Yes |

## Limits

- The SQL ran against the regenerated source data, not against the deployed PostgreSQL tables. No
  database session was opened in the cluster.
- The match shows that the deployed API serves the totals that the documented definitions give for
  the documented dataset.
