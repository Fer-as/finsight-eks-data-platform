import Trend from "./components/Trend.jsx";
import { useEffect, useState } from "react";
import { getJson, money, nextMonth, percentage } from "./lib.js";

export default function App() {
  const [departments, setDepartments] = useState([]);
  const [department, setDepartment] = useState("");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [configured, setConfigured] = useState(false);
  const [level, setLevel] = useState("high");
  const [page, setPage] = useState(0);
  const [reload, setReload] = useState(0);
  const [state, setState] = useState({ loading: true });

  useEffect(() => {
    const controller = new AbortController();
    getJson("/api/config", controller.signal)
      .then((config) => {
        setStart((current) => current || config.start_month);
        setEnd((current) => current || config.end_month);
        setConfigured(true);
      })
      .catch((error) => {
        if (error.name !== "AbortError") setState({ error: error.message });
      });
    return () => controller.abort();
  }, [reload]);

  useEffect(() => {
    const controller = new AbortController();
    if (!configured) return () => controller.abort();
    if (!start || !end || start > end) {
      setState({
        error:
          "Choose a valid reporting period. Start month must precede or equal end month.",
      });
      return () => controller.abort();
    }
    setState({ loading: true });
    const query = new URLSearchParams({
      start: `${start}-01`,
      end: nextMonth(end),
    });
    if (department) query.set("department", department);
    const transactions = new URLSearchParams(query);
    transactions.set("limit", "10");
    transactions.set("offset", String(page * 10));
    if (level) transactions.set("level", level);
    Promise.all([
      getJson(`/api/dashboard?${query}`, controller.signal),
      getJson(`/api/transactions?${transactions}`, controller.signal),
      getJson("/api/departments", controller.signal),
    ])
      .then(([dashboard, txns, options]) => {
        setDepartments(options);
        setState({ dashboard, txns });
      })
      .catch((error) => {
        if (error.name !== "AbortError") setState({ error: error.message });
      });
    return () => controller.abort();
  }, [department, start, end, level, page, reload, configured]);

  const change = (setter) => (event) => {
    setter(event.target.value);
    setPage(0);
  };
  const data = state.dashboard;
  return (
    <div className="shell">
      <aside className="sidebar">
        <a className="brand" href="/" aria-label="FinSight home">
          <span className="brand-icon">F</span> FinSight
          <span className="brand-dot">.</span>
        </a>
        <div className="workspace-label">INTELLIGENCE WORKSPACE</div>
        <nav aria-label="Sections">
          <a className="active" href="#overview">
            <span>◫</span> Overview
          </a>
          <a href="#performance">
            <span>▥</span> Financial performance
          </a>
          <a href="#departments">
            <span>▦</span> Department budgets
          </a>
          <a href="#risk">
            <span>◇</span> Transaction risk
          </a>
        </nav>
        <div className="sidebar-footer">
          <span className="status-dot" /> LOCAL ENVIRONMENT
          <p>
            Financial clarity.
            <br />
            Built on reliable data.
          </p>
          <small>Day 1 · Platform foundation</small>
        </div>
      </aside>
      <main id="overview">
        <div className="topline">
          <span>WORKSPACE / OVERVIEW</span>
          <span className="demo-tag">SYNTHETIC DATA ONLY</span>
        </div>
        <header>
          <div>
            <p className="eyebrow">THE BIG PICTURE</p>
            <h1>Financial overview</h1>
            <p className="subtitle">
              Performance, budgets and transaction signals in one place.
            </p>
          </div>
          <button onClick={() => setReload((value) => value + 1)}>
            ↻ Refresh data
          </button>
        </header>
        <section className="filters" aria-label="Report filters">
          <label>
            From month
            <input type="month" value={start} onChange={change(setStart)} />
          </label>
          <label>
            Through month
            <input type="month" value={end} onChange={change(setEnd)} />
          </label>
          <label>
            Department
            <select value={department} onChange={change(setDepartment)}>
              <option value="">All departments</option>
              {departments.map((d) => (
                <option key={d.id} value={d.id}>
                  {d.name}
                </option>
              ))}
            </select>
          </label>
          <span className="currency-label">
            Reporting currency <strong>GBP £</strong>
          </span>
        </section>
        {state.loading && (
          <div className="notice" role="status">
            Loading financial intelligence…
          </div>
        )}
        {state.error && (
          <div className="notice error" role="alert">
            {state.error}
          </div>
        )}
        {data && (
          <>
            {!data.has_data && (
              <div className="notice" role="status">
                No financial records for this period. Run the ETL or choose
                another period.
              </div>
            )}
            <section className="kpis" aria-label="Financial KPIs">
              {[
                [
                  "Total revenue",
                  money(data.summary.revenue),
                  "Recognised revenue entries",
                ],
                [
                  "Total expenses",
                  money(data.summary.expenses),
                  "Operating expense entries",
                ],
                [
                  "Operating profit",
                  money(data.summary.profit),
                  "Revenue less expenses",
                ],
                [
                  "Profit margin",
                  percentage(data.summary.margin_percent),
                  "Operating profit / revenue",
                ],
              ].map(([label, value, detail], index) => (
                <article
                  key={label}
                  className={`kpi ${index === 2 ? "highlight" : ""}`}
                >
                  <p>
                    {label}
                    <span>↗</span>
                  </p>
                  <strong>{value}</strong>
                  <small>{detail}</small>
                </article>
              ))}
            </section>
            <div className="performance-grid">
              <section className="panel" id="performance">
                <div className="panel-heading">
                  <div>
                    <h2>Revenue & expenses</h2>
                    <p>Monthly performance · GBP</p>
                  </div>
                  <div className="legend">
                    <span>● Revenue</span>
                    <span>● Expenses</span>
                  </div>
                </div>
                {data.monthly.length ? (
                  <>
                    <Trend rows={data.monthly} />
                    <details>
                      <summary>View monthly figures</summary>
                      <div className="table-wrap">
                        <table>
                          <thead>
                            <tr>
                              <th>Month</th>
                              <th>Revenue</th>
                              <th>Expenses</th>
                              <th>Profit</th>
                            </tr>
                          </thead>
                          <tbody>
                            {data.monthly.map((row) => (
                              <tr key={row.month}>
                                <td>{row.month.slice(0, 7)}</td>
                                <td>{money(row.revenue)}</td>
                                <td>{money(row.expenses)}</td>
                                <td>{money(row.profit)}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    </details>
                  </>
                ) : (
                  <p className="empty">No trend data available.</p>
                )}
              </section>
              <section className="panel budget-card">
                <p className="eyebrow">BUDGET POSITION</p>
                <h2>Room to operate</h2>
                <strong
                  className={
                    data.summary.budget_variance.startsWith("-")
                      ? "negative budget-number"
                      : "budget-number"
                  }
                >
                  {money(data.summary.budget_variance)}
                </strong>
                <p>
                  Budget less actual expenses.
                  <br />
                  Positive means under budget.
                </p>
                <dl>
                  <div>
                    <dt>Expense budget</dt>
                    <dd>{money(data.summary.expense_budget)}</dd>
                  </div>
                  <div>
                    <dt>Budget used</dt>
                    <dd>
                      {percentage(data.summary.budget_utilisation_percent)}
                    </dd>
                  </div>
                </dl>
                <span className="subtle-tag">Complete calendar months</span>
              </section>
            </div>
            <section className="panel" id="departments">
              <div className="panel-heading">
                <div>
                  <h2>Department performance</h2>
                  <p>Expense budgets compared with actuals</p>
                </div>
                <span className="subtle-tag">
                  {data.departments.length} departments
                </span>
              </div>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Department</th>
                      <th>Revenue</th>
                      <th>Expenses</th>
                      <th>Budget</th>
                      <th>Variance</th>
                      <th>Used</th>
                    </tr>
                  </thead>
                  <tbody>
                    {data.departments.map((row) => (
                      <tr key={row.id}>
                        <td className="department-name">{row.name}</td>
                        <td>{money(row.revenue)}</td>
                        <td>{money(row.expenses)}</td>
                        <td>{money(row.expense_budget)}</td>
                        <td
                          className={
                            row.budget_variance.startsWith("-")
                              ? "negative"
                              : "positive"
                          }
                        >
                          {money(row.budget_variance)}
                        </td>
                        <td>{percentage(row.budget_utilisation_percent)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
            <section className="panel" id="risk">
              <div className="panel-heading">
                <div>
                  <h2>Transaction risk signals</h2>
                  <p>Rule-based review indicators · not confirmed fraud</p>
                </div>
                <label className="inline-label">
                  Show
                  <select value={level} onChange={change(setLevel)}>
                    <option value="high">High indicators</option>
                    <option value="medium">Medium indicators</option>
                    <option value="low">Low indicators</option>
                    <option value="">All transactions</option>
                  </select>
                </label>
              </div>
              <div className="risk-summary">
                <span>
                  <strong>{data.risk.total.toLocaleString("en-GB")}</strong>{" "}
                  transactions
                </span>
                <span>
                  <strong>{data.risk.flagged.toLocaleString("en-GB")}</strong>{" "}
                  flagged for review
                </span>
                <span>
                  <strong>{data.risk.high}</strong> high indicators
                </span>
                <span>
                  <strong>{money(data.risk.volume)}</strong> transaction volume
                </span>
              </div>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>Transaction / UTC</th>
                      <th>Synthetic account</th>
                      <th>Amount</th>
                      <th>Level</th>
                      <th>Reason</th>
                    </tr>
                  </thead>
                  <tbody>
                    {state.txns.items.map((tx) => (
                      <tr key={tx.id}>
                        <td>
                          <span className="transaction-id">{tx.id}</span>
                          <small>
                            {new Date(tx.occurred_at).toLocaleString("en-GB", {
                              timeZone: "UTC",
                            })}
                          </small>
                        </td>
                        <td>{tx.account_ref}</td>
                        <td>{money(tx.amount)}</td>
                        <td>
                          <span className={`risk-badge ${tx.risk_level}`}>
                            {tx.risk_level}
                          </span>
                        </td>
                        <td>
                          {tx.reasons.length
                            ? tx.reasons
                                .map((reason) => reason.replaceAll("_", " "))
                                .join(" · ")
                            : "No rule triggered"}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              {!state.txns.items.length && (
                <p className="empty">No transactions match these filters.</p>
              )}
              <div className="pagination">
                <span>
                  {state.txns.total.toLocaleString("en-GB")} matching
                  transactions
                </span>
                <div>
                  <button
                    disabled={page === 0}
                    onClick={() => setPage(page - 1)}
                  >
                    Previous
                  </button>
                  <span>Page {page + 1}</span>
                  <button
                    disabled={(page + 1) * 10 >= state.txns.total}
                    onClick={() => setPage(page + 1)}
                  >
                    Next
                  </button>
                </div>
              </div>
            </section>
            <footer>
              FinSight · Deterministic synthetic data · GBP
              {data.latest_pipeline && (
                <span>
                  ETL run #{data.latest_pipeline.id} · Source{" "}
                  {data.latest_pipeline.source_sha256.slice(0, 12)}
                </span>
              )}
            </footer>
          </>
        )}
      </main>
    </div>
  );
}
