// Amounts arrive as exact decimal strings. BigInt keeps money formatting lossless.
export function money(value = "0.00") {
  const negative = value.startsWith("-");
  const [whole, fraction = "00"] = value.replace("-", "").split(".");
  return `${negative ? "-" : ""}£${BigInt(whole).toLocaleString("en-GB")}.${fraction.padEnd(2, "0")}`;
}

export function percentage(value) {
  return value === null || value === undefined ? "N/A" : `${value}%`;
}

export async function getJson(path, signal) {
  const response = await fetch(path, { signal });
  if (!response.ok)
    throw new Error(
      `Unable to load analytics (${response.status}). Check the API and database.`,
    );
  return response.json();
}

export function nextMonth(month) {
  const [year, number] = month.split("-").map(Number);
  return `${number === 12 ? year + 1 : year}-${String(number === 12 ? 1 : number + 1).padStart(2, "0")}-01`;
}
