/**
 * Tiny helpers shared by every challenge component.
 *
 * Why these helpers exist:
 *  - On-chain values are `bigint` with 18 decimals (1 ETH = 1_000_000_000_000_000_000n).
 *    viem ships `parseUnits`/`formatUnits` to convert between human strings and
 *    bigints — we wrap them with safe defaults so a workshop attendee can't
 *    crash the page by typing nothing or "abc".
 *  - `useEventLog` is a 5-line replacement for a real toast/notification system
 *    so each section can show its own append-only log.
 */
import { useState } from "react";
import { formatUnits, parseUnits } from "viem";

/**
 * Tiny pass-through that widens the argument type for `writeContract(Async)`.
 *
 * Wagmi v2's TS overloads sometimes over-narrow when an ABI is `as const` and a
 * single function is selected, then complain that `account`/`chain` are missing
 * (they're not — the connector supplies them at runtime). Wrapping the config
 * with `wc(...)` sidesteps that without losing the field-level docs.
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const wc = <T>(cfg: T): any => cfg;

/** Format a bigint (wei, 18 decimals) for display. Returns "0" if undefined. */
export const fmt = (v: bigint | undefined, decimals = 18, precision = 4) => {
  if (v === undefined) return "0";
  const [int, frac = ""] = formatUnits(v, decimals).split(".");
  return frac ? `${int}.${frac.slice(0, precision)}` : int;
};

/** Parse a user-typed string into a bigint with 18 decimals. Returns 0n on bad input. */
export const safeParse = (input: string, decimals = 18): bigint => {
  if (!input || isNaN(Number(input))) return 0n;
  try { return parseUnits(input, decimals); } catch { return 0n; }
};

/** Append-only log buffer rendered inside an <output>/<pre> for each challenge. */
export function useEventLog(maxLines = 50) {
  const [lines, setLines] = useState<string[]>([]);
  const push = (msg: string) =>
    setLines((p) => [`[${new Date().toLocaleTimeString()}] ${msg}`, ...p].slice(0, maxLines));
  return { lines, push };
}
