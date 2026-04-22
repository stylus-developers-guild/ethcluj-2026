/**
 * Challenge 3 — DEX (constant-product AMM).
 *
 *   x * y = k   where  x = reserve1 (CUSD), y = reserve2 (WETH)
 *
 * Each swap pulls `amountIn` of one token out of the user's wallet (hence the
 * approve) and sends back the amount that keeps `x*y` constant.
 *
 * NEW PATTERN — `useWatchContractEvent`:
 *   Subscribes to on-chain logs in real time (via the RPC's `eth_newFilter`
 *   or polling fallback). Every time the contract emits `Swap`, we get the
 *   decoded args and append them to our log buffer.
 */
import { useState } from "react";
import { useAccount, useReadContract, useWatchContractEvent, useWriteContract } from "wagmi";
import { ADDRESSES, dexAbi, erc20Abi } from "@/lib/contracts";
import { fmt, safeParse, useEventLog, wc } from "@/lib/utils-eth";

type Direction = "cusd-weth" | "weth-cusd";

export default function Dex() {
  const { address } = useAccount();
  const [direction, setDirection] = useState<Direction>("cusd-weth");
  const [amount, setAmount] = useState("");
  const log = useEventLog();

  // READS — pool reserves are public state on the DEX.
  const { data: r1, refetch: refetchR1 } = useReadContract({ address: ADDRESSES.dex, abi: dexAbi, functionName: "reserve1" });
  const { data: r2, refetch: refetchR2 } = useReadContract({ address: ADDRESSES.dex, abi: dexAbi, functionName: "reserve2" });

  const { writeContractAsync, isPending } = useWriteContract();

  // EVENT SUBSCRIPTION — fires whenever ANY swap happens on this pool.
  useWatchContractEvent({
    address: ADDRESSES.dex,
    abi: dexAbi,
    eventName: "Swap",
    onLogs: (logs) => {
      logs.forEach((l) => {
        // `l.args` is fully typed from the const ABI above.
        const { amountIn, amountOut } = l.args as { amountIn: bigint; amountOut: bigint };
        log.push(`Swap in=${fmt(amountIn)} out=${fmt(amountOut)}`);
      });
      refetchR1(); refetchR2();
    },
  });

  const onSubmit = async () => {
    if (!address) return;
    const value = safeParse(amount);
    // The DEX uses transferFrom, so we approve the input token first.
    const tokenIn = direction === "cusd-weth" ? ADDRESSES.cusd : ADDRESSES.weth;
    const swapFn  = direction === "cusd-weth" ? "swapToken1ForToken2" : "swapToken2ForToken1";
    try {
      const a = await writeContractAsync(wc({
        address: tokenIn, abi: erc20Abi, functionName: "approve",
        args: [ADDRESSES.dex, value],
      }));
      log.push(`approve: ${a.slice(0, 10)}…`);
      const s = await writeContractAsync(wc({
        address: ADDRESSES.dex, abi: dexAbi, functionName: swapFn, args: [value],
      }));
      log.push(`swap: ${s.slice(0, 10)}…`);
    } catch (e) {
      log.push(`swap failed: ${(e as Error).message.split("\n")[0]}`);
    }
  };

  // Spot price = reserve1 / reserve2 (both are 1e18-scaled bigints).
  // Multiply numerator by 1e18 *before* dividing to keep precision.
  const price = r1 && r2 && r2 > 0n ? fmt((r1 * 10n ** 18n) / r2) : "0";

  return (
    <>
      <h2>3. DEX</h2>
      <section>
        <article>
          <h3>Actions</h3>
          <label><span>Action</span>
            <select value={direction} onChange={(e) => setDirection(e.target.value as Direction)}>
              <option value="cusd-weth">Swap CUSD → WETH</option>
              <option value="weth-cusd">Swap WETH → CUSD</option>
            </select>
          </label>
          <label><span>Amount</span>
            <input type="number" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
          <button onClick={onSubmit} disabled={!address || isPending}>Submit</button>
        </article>
        <article>
          <h3>State</h3>
          <dl>
            <dt>CUSD Reserve:</dt><dd>{fmt(r1)}</dd>
            <dt>WETH Reserve:</dt><dd>{fmt(r2)}</dd>
            <dt>Price (CUSD / WETH):</dt><dd>{price}</dd>
          </dl>
        </article>
        <article>
          <h3>Events / Logs</h3>
          <output>{log.lines.join("\n") || "No events yet..."}</output>
        </article>
      </section>
    </>
  );
}
