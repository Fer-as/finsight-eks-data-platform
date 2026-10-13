import { money } from "../lib.js";

export default function Trend({ rows }) {
  // Floating point is used only for chart geometry, never financial calculations.
  const maximum = Math.max(
    1,
    ...rows.flatMap((row) => [Number(row.revenue), Number(row.expenses)]),
  );
  return (
    <div
      className="chart"
      role="img"
      aria-label="Monthly revenue and expenses bar chart"
    >
      {rows.map((row) => (
        <div className="chart-month" key={row.month}>
          <div className="bars">
            <div
              className="bar revenue"
              style={{ height: `${(Number(row.revenue) / maximum) * 100}%` }}
              title={`Revenue: ${money(row.revenue)}`}
            />
            <div
              className="bar expense"
              style={{ height: `${(Number(row.expenses) / maximum) * 100}%` }}
              title={`Expenses: ${money(row.expenses)}`}
            />
          </div>
          <span>
            {new Date(`${row.month}T00:00:00Z`).toLocaleDateString("en-GB", {
              month: "short",
              timeZone: "UTC",
            })}
          </span>
        </div>
      ))}
    </div>
  );
}
