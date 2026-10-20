import { afterEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";
import App from "./App.jsx";
import { money, nextMonth } from "./lib.js";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const metrics = {
  revenue: "100.01",
  expenses: "80.00",
  profit: "20.01",
  margin_percent: "20.01",
  expense_budget: "90.00",
  budget_variance: "10.00",
  budget_utilisation_percent: "88.89",
};
const dashboard = {
  has_data: true,
  summary: metrics,
  monthly: [{ month: "2025-01-01", ...metrics }],
  departments: [{ id: "retail", name: "Retail Banking", ...metrics }],
  risk: { total: 1, flagged: 1, high: 1, volume: "10000.00" },
  latest_pipeline: null,
};

function mockApi(data = dashboard) {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (url) => ({
      ok: true,
      json: async () =>
        url === "/api/config"
          ? { start_month: "2025-01", end_month: "2025-12" }
          : url.startsWith("/api/dashboard")
            ? data
            : url.startsWith("/api/departments")
              ? [{ id: "retail", name: "Retail Banking" }]
              : { items: [], total: 0 },
    })),
  );
}

describe("FinSight", () => {
  it("formats exact GBP without floating-point rounding", () => {
    expect(money("90071992547409.93")).toBe("£90,071,992,547,409.93");
    expect(money("-0.01")).toBe("-£0.01");
    expect(nextMonth("2025-12")).toBe("2026-01-01");
  });

  it("shows loading state", () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => new Promise(() => {})),
    );
    render(<App />);
    expect(screen.getByRole("status").textContent).toContain("Loading");
  });

  it("shows server failures with a retry action", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async () => ({ ok: false, status: 503 })),
    );
    render(<App />);
    expect((await screen.findByRole("alert")).textContent).toContain("503");
    expect(screen.getByRole("button", { name: /Refresh/ })).toBeTruthy();
  });

  it("renders API results and sends selected department to the API", async () => {
    mockApi();
    render(<App />);
    await screen.findByText("Operating profit");
    expect(screen.getAllByText("£100.01").length).toBeGreaterThan(0);
    fireEvent.change(screen.getByLabelText("Department"), {
      target: { value: "retail" },
    });
    await waitFor(() =>
      expect(
        fetch.mock.calls.some(([url]) => url.includes("department=retail")),
      ).toBe(true),
    );
    expect(screen.getByText(/not confirmed fraud/)).toBeTruthy();
  });

  it("labels the data as a synthetic demonstration, not a live environment", async () => {
    mockApi();
    render(<App />);
    await screen.findByText("Operating profit");
    expect(screen.queryByText(/LOCAL ENVIRONMENT/i)).toBeNull();
    expect(screen.getByText("DEMO DATA")).toBeTruthy();
    expect(screen.getByText("SYNTHETIC DATA ONLY")).toBeTruthy();
    expect(
      screen.getByText(/not connected to any live financial system/),
    ).toBeTruthy();
  });

  it("shows empty periods rather than invented values", async () => {
    mockApi({ ...dashboard, has_data: false, monthly: [] });
    render(<App />);
    expect(
      await screen.findByText(/No financial records for this period/),
    ).toBeTruthy();
  });

  it("rejects reversed date filters locally", async () => {
    mockApi();
    render(<App />);
    await screen.findByText("Operating profit");
    fireEvent.change(screen.getByLabelText("From month"), {
      target: { value: "2026-01" },
    });
    expect((await screen.findByRole("alert")).textContent).toContain(
      "valid reporting period",
    );
  });
});
