CREATE SCHEMA IF NOT EXISTS curated;
CREATE SCHEMA IF NOT EXISTS ops;

CREATE TABLE curated.departments (
    id text PRIMARY KEY,
    name text NOT NULL
);
CREATE TABLE curated.entries (
    id text PRIMARY KEY,
    booked_on date NOT NULL,
    department_id text NOT NULL REFERENCES curated.departments(id),
    kind text NOT NULL CHECK (kind IN ('revenue', 'expense')),
    amount_pence bigint NOT NULL CHECK (amount_pence > 0),
    currency text NOT NULL CHECK (currency = 'GBP')
);
CREATE TABLE curated.budgets (
    month date NOT NULL CHECK (EXTRACT(DAY FROM month) = 1),
    department_id text NOT NULL REFERENCES curated.departments(id),
    amount_pence bigint NOT NULL CHECK (amount_pence > 0),
    currency text NOT NULL CHECK (currency = 'GBP'),
    PRIMARY KEY (month, department_id)
);
CREATE TABLE curated.transactions (
    id text PRIMARY KEY,
    occurred_at timestamptz NOT NULL,
    department_id text NOT NULL REFERENCES curated.departments(id),
    account_ref text NOT NULL,
    amount_pence bigint NOT NULL CHECK (amount_pence > 0),
    currency text NOT NULL CHECK (currency = 'GBP'),
    risk_level text NOT NULL CHECK (risk_level IN ('low', 'medium', 'high')),
    risk_reasons text NOT NULL
);
CREATE INDEX ON curated.entries (booked_on, department_id);
CREATE INDEX ON curated.transactions (occurred_at, department_id);
CREATE TABLE ops.pipeline_runs (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at timestamptz NOT NULL DEFAULT now(),
    finished_at timestamptz,
    status text NOT NULL CHECK (status IN ('running', 'succeeded', 'failed')),
    source_sha256 text NOT NULL,
    counts jsonb NOT NULL DEFAULT '{}',
    error text
);
