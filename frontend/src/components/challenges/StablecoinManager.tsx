/**
 * Challenge 2 — Stablecoin Manager (a tiny MakerDAO).
 *
 * The contract has 4 user-facing actions:
 *   deposit(amount)  → user gives the manager WETH as collateral
 *   withdraw(amount) → user pulls WETH back (must keep ratio ≥ 150%)
 *   mint(amount)     → user mints CUSD against their collateral
 *   burn(amount)     → user repays CUSD debt
 *
 * KEY PATTERN — "approve then act":
 *   `Manager.deposit()` internally calls `weth.transferFrom(user, manager, amount)`.
 *   ERC20.transferFrom requires the user to have previously called
 *   `weth.approve(manager, amount)`. So a deposit is ALWAYS two on-chain txs.
 *
 *   We use `writeContractAsync` (Promise-returning) so we can `await` the
 *   approve and only then send the deposit — giving the user a single click.
 */
import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDRESSES, erc20Abi, managerAbi } from "@/lib/contracts";
import { fmt, safeParse, useEventLog, wc } from "@/lib/utils-eth";

type Action = "deposit" | "withdraw" | "mint" | "burn";

export default function StablecoinManager() {
  const { address } = useAccount();
  const [action, setAction] = useState<Action>("deposit");
  const [amount, setAmount] = useState("");
  const log = useEventLog();

  // READS — three per-user values + the global minimum collateral ratio.
  // Every read shares the same `address`/`abi` so we factor those out.
  const base = { address: ADDRESSES.manager, abi: managerAbi, query: { enabled: !!address } } as const;
  const userArg = address ? ([address] as const) : undefined;
  const { data: deposited, refetch: r1 } = useReadContract({ ...base, functionName: "depositAmountOf", args: userArg });
  const { data: minted,    refetch: r2 } = useReadContract({ ...base, functionName: "mintedAmountOf",  args: userArg });
  const { data: ratio,     refetch: r3 } = useReadContract({ ...base, functionName: "collatRatio",     args: userArg });
  const { data: minRatio } = useReadContract({ address: ADDRESSES.manager, abi: managerAbi, functionName: "MIN_COLLAT_RATIO" });

  const { writeContractAsync, isPending } = useWriteContract();

  const onSubmit = async () => {
    if (!address) return;
    const value = safeParse(amount);
    try {
      // Step 1 — approve when the action will pull tokens from the user.
      // (deposit needs WETH, burn needs CUSD; mint/withdraw don't pull anything.)
      if (action === "deposit") {
        const h = await writeContractAsync(wc({
          address: ADDRESSES.weth, abi: erc20Abi, functionName: "approve",
          args: [ADDRESSES.manager, value],
        }));
        log.push(`approve WETH: ${h.slice(0, 10)}…`);
      }
      // Step 2 — call the actual Manager function. `functionName` is typed
      // as one of {deposit,withdraw,mint,burn} thanks to the const-asserted ABI.
      const hash = await writeContractAsync(wc({
        address: ADDRESSES.manager, abi: managerAbi, functionName: action, args: [value],
      }));
      log.push(`${action} tx: ${hash.slice(0, 10)}…`);
      r1(); r2(); r3();
    } catch (e) {
      log.push(`${action} failed: ${(e as Error).message.split("\n")[0]}`);
    }
  };

  // collatRatio is scaled by 1e18 (so 1.5e18 = 150%). We render it as a %.
  // `type(uint256).max` is returned when the user has no debt — show "∞".
  const pct = (v?: bigint) =>
    v === undefined ? "—" : v === 2n ** 256n - 1n ? "∞" : `${Number(v / 10n ** 16n)}%`;

  return (
    <>
      <h2>2. Stablecoin Manager</h2>
      <section>
        <article>
          <h3>Actions</h3>
          <label><span>Action</span>
            <select value={action} onChange={(e) => setAction(e.target.value as Action)}>
              <option value="deposit">Deposit WETH</option>
              <option value="withdraw">Withdraw WETH</option>
              <option value="mint">Mint CUSD</option>
              <option value="burn">Burn CUSD</option>
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
            <dt>Deposited WETH:</dt><dd>{fmt(deposited)}</dd>
            <dt>Minted CUSD:</dt><dd>{fmt(minted)}</dd>
            <dt>Collateral Ratio:</dt><dd>{pct(ratio)}</dd>
            <dt>Min Collateral Ratio:</dt><dd>{pct(minRatio)}</dd>
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
