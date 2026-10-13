"""Read-only reporting. Aggregate facts separately to prevent budget fan-out."""

from decimal import ROUND_HALF_UP, Decimal

from psycopg.rows import dict_row


def pounds(pence) -> str:
    return f"{Decimal(pence or 0) / 100:.2f}"


def percent(numerator, denominator) -> str | None:
    if not denominator:
        return None
    return str(
        (Decimal(numerator) * 100 / Decimal(denominator)).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
    )


def report(connection, start, end, department: str | None) -> dict:
    params = dict(start=start, end=end, department=department)
    with connection.cursor(row_factory=dict_row) as cursor:
        # Budget comparisons intentionally use complete calendar months only.
        cursor.execute(
            """
            WITH actuals AS (
              SELECT date_trunc('month', booked_on)::date AS month, department_id,
                     sum(amount_pence) FILTER (WHERE kind='revenue') AS revenue,
                     sum(amount_pence) FILTER (WHERE kind='expense') AS expenses
              FROM curated.entries
              WHERE booked_on >= %(start)s AND booked_on < %(end)s
                AND (%(department)s::text IS NULL OR department_id = %(department)s)
              GROUP BY 1, 2
            ), budgets AS (
              SELECT month, department_id, sum(amount_pence) AS budget
              FROM curated.budgets
              WHERE month >= %(start)s AND month < %(end)s
                AND (%(department)s::text IS NULL OR department_id = %(department)s)
              GROUP BY 1, 2
            )
            SELECT coalesce(a.month,b.month) AS month,
                   coalesce(a.department_id,b.department_id) AS department_id,
                   coalesce(a.revenue,0) AS revenue, coalesce(a.expenses,0) AS expenses,
                   coalesce(b.budget,0) AS budget
            FROM actuals a FULL JOIN budgets b USING (month,department_id)
            ORDER BY 1, 2
        """,
            params,
        )
        rows = cursor.fetchall()
        cursor.execute("SELECT id, name FROM curated.departments ORDER BY name")
        departments = cursor.fetchall()
        cursor.execute(
            """
            SELECT count(*) AS total, count(*) FILTER (WHERE risk_level != 'low') AS flagged,
                   count(*) FILTER (WHERE risk_level = 'high') AS high,
                   coalesce(sum(amount_pence),0) AS volume
            FROM curated.transactions
            WHERE occurred_at >= %(start)s::date::timestamp AT TIME ZONE 'UTC'
              AND occurred_at < %(end)s::date::timestamp AT TIME ZONE 'UTC'
              AND (%(department)s::text IS NULL OR department_id = %(department)s)
        """,
            params,
        )
        risk = cursor.fetchone()
        cursor.execute("""SELECT id, finished_at, source_sha256, counts FROM ops.pipeline_runs
                          WHERE status='succeeded' ORDER BY id DESC LIMIT 1""")
        latest = cursor.fetchone()

    def metrics(records):
        revenue = sum(r["revenue"] for r in records)
        expenses = sum(r["expenses"] for r in records)
        budget = sum(r["budget"] for r in records)
        return dict(
            revenue=pounds(revenue),
            expenses=pounds(expenses),
            profit=pounds(revenue - expenses),
            margin_percent=percent(revenue - expenses, revenue),
            expense_budget=pounds(budget),
            budget_variance=pounds(budget - expenses),
            budget_utilisation_percent=percent(expenses, budget),
        )

    months = sorted({row["month"] for row in rows})
    return dict(
        currency="GBP",
        start=start,
        end_exclusive=end,
        has_data=bool(rows),
        summary=metrics(rows),
        monthly=[
            dict(month=month.isoformat(), **metrics([r for r in rows if r["month"] == month]))
            for month in months
        ],
        departments=[
            dict(**d, **metrics([r for r in rows if r["department_id"] == d["id"]]))
            for d in departments
            if department is None or d["id"] == department
        ],
        risk=dict(
            total=risk["total"],
            flagged=risk["flagged"],
            high=risk["high"],
            volume=pounds(risk["volume"]),
            flagged_percent=percent(risk["flagged"], risk["total"]),
        ),
        latest_pipeline=latest,
    )


def transactions(connection, start, end, department, level, limit, offset) -> dict:
    where = """occurred_at >= %(start)s::date::timestamp AT TIME ZONE 'UTC'
        AND occurred_at < %(end)s::date::timestamp AT TIME ZONE 'UTC'
        AND (%(department)s::text IS NULL OR department_id=%(department)s)
        AND (%(level)s::text IS NULL OR risk_level=%(level)s)"""
    params = dict(
        start=start, end=end, department=department, level=level, limit=limit, offset=offset
    )
    with connection.cursor(row_factory=dict_row) as cursor:
        cursor.execute(f"SELECT count(*) AS total FROM curated.transactions WHERE {where}", params)
        total = cursor.fetchone()["total"]
        cursor.execute(
            f"""SELECT id, occurred_at, department_id, account_ref, amount_pence,
                           risk_level, risk_reasons FROM curated.transactions WHERE {where}
                           ORDER BY occurred_at DESC, id LIMIT %(limit)s OFFSET %(offset)s""",
            params,
        )
        items = cursor.fetchall()
    for item in items:
        item["amount"] = pounds(item.pop("amount_pence"))
        reasons = item.pop("risk_reasons")
        item["reasons"] = reasons.split(",") if reasons else []
    return dict(items=items, total=total, limit=limit, offset=offset, currency="GBP")
