# Data contract and KPI definitions

All figures are synthetic GBP. Source monetary values and database columns are positive
integer **pence**. API monetary values are decimal pound **strings**, always two decimal
places. JavaScript formats them through BigInt. Floating point is used only for bar heights.
Ratios use Python Decimal with round-half-up to two decimal percentage points.

| Measure | Definition | Edge case |
|---|---|---|
| Revenue | Sum of `revenue` entries | Zero for no entries |
| Expenses | Sum of `expense` entries | Zero for no entries |
| Operating profit | Revenue − expenses | Can be negative; simplified pre-tax demo measure |
| Profit margin | 100 × operating profit / revenue | `null` / N/A when revenue is zero |
| Expense budget | Sum of monthly departmental budgets | Zero for no budgets |
| Budget variance | Expense budget − actual expenses | Positive is favourable / under budget |
| Budget utilisation | 100 × expenses / expense budget | `null` / N/A when budget is zero |
| Transaction volume | Sum of banking transaction amounts | Flow volume, never added to revenue |
| Flagged transactions | Count with medium or high indicator | Not a count of confirmed fraud |
| Flagged percentage | 100 × flagged / total transactions | `null` when there are no transactions |

## Grain and filtering

- Departments: one row per department ID.
- Entries: one row per entry ID, booking date and department; revenue and expenses are
  independently simulated business entries, not a double-entry accounting ledger.
- Budgets: exactly one expense budget per department and calendar month.
- Transactions: one row per synthetic transaction ID, timestamp and account reference.
- Reporting windows include `start` and exclude `end`. Both must be month starts.
  The UI's “Through month” is inclusive and becomes the following month in the API.
- Banking timestamps are normalised to UTC. Overnight and period filters use UTC.
- Aggregate entries and budgets **separately** by department/month, then join. Joining
  individual entries to monthly budgets would multiply the budget.
- Department filters apply to financial and banking results. A missing department
  returns an empty dataset rather than an invented value.
- Empty financial periods display an explicit empty state. Missing denominators are N/A.

## Rule-based indicators

Thresholds live in `config/synthetic.json` and are materialised during ETL. Re-run ETL
after changes. Defaults:

- `high_value`: amount ≥ 1,000,000 pence (£10,000).
- `overnight`: UTC hour < 6 (00:00:00 through 05:59:59).
- High: both rules. Medium: exactly one. Low: neither.

These are deliberately simple review indicators, with no customer profiling, model
training or claims of fraud detection. Generator-injected high cases occur every 97th
transaction; expected labels are not supplied as detector inputs.

## ETL quality and reproducibility

Default seed 42 and fixed year 2025 produce 3 departments, 288 entries, 36 budgets
and 10,000 banking transactions. Generator order and IDs are deterministic.

Required columns are checked exactly. Malformed records (including fractional pence,
unsupported currency, invalid dates, unknown departments and naive timestamps) are
quarantined with reasons. Reconciliation is source = accepted + rejected + duplicates.
Exact duplicate keys/values are collapsed; conflicting duplicates fail the run.
Any table with no accepted records fails the run, preserving the previous database snapshot.

The loader replaces the small complete snapshot within one transaction. Foreign-key or
other load failures roll back every table. Re-runs add an audit record but do not multiply
business data. Files are retained by source/config hash; generated raw files are overwritten
when generation is explicitly repeated. This is a local full-refresh batch design, not
an incremental production ingestion system.
