/**
 * Challenge 4a — TokenVault (ERC4626-style share accounting).
 *
 *   depositTokens(amount)  → user supplies CUSD, gets `shares` proportional
 *                            to the pool's existing shares/balance ratio.
 *   withdrawTokens(shares) → burn shares, receive amount * (vaultBalance/totalShares).
 *
 * The "exchange rate" between shares and CUSD changes whenever the vault's
 * CUSD balance grows (e.g. flash-loan fees in a real protocol).
 *
 * Notice we read the vault's CUSD balance via the *CUSD* ERC20 contract, not
 * the vault — because that's where the accounting actually lives.
 */
import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDRESSES, erc20Abi, vaultAbi } from "@/lib/contracts";
import { fmt, safeParse, useEventLog, wc } from "@/lib/utils-eth";

type Action = "deposit" | "withdraw";

export default function Vault() {
  const { address } = useAccount();
  const [action, setAction] = useState<Action>("deposit");
  const [amount, setAmount] = useState("");
  const log = useEventLog();

  const { data: vaultBal, refetch: rb } = useReadContract({
    address: ADDRESSES.cusd, abi: erc20Abi, functionName: "balanceOf",
    args: [ADDRESSES.vault],
  });
  const { data: total,  refetch: rt } = useReadContract({ address: ADDRESSES.vault, abi: vaultAbi, functionName: "totalShares" });
  const { data: shares, refetch: rs } = useReadContract({
    address: ADDRESSES.vault, abi: vaultAbi, functionName: "sharesOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  const { writeContractAsync, isPending } = useWriteContract();

  const onSubmit = async () => {
    if (!address) return;
    const value = safeParse(amount);
    try {
      if (action === "deposit") {
        // depositTokens uses transferFrom → approve CUSD first.
        const a = await writeContractAsync(wc({
          address: ADDRESSES.cusd, abi: erc20Abi, functionName: "approve",
          args: [ADDRESSES.vault, value],
        }));
        log.push(`approve: ${a.slice(0, 10)}…`);
        const d = await writeContractAsync(wc({
          address: ADDRESSES.vault, abi: vaultAbi, functionName: "depositTokens", args: [value],
        }));
        log.push(`deposit: ${d.slice(0, 10)}…`);
      } else {
        // Withdraw burns SHARES (not CUSD), so no approve is needed.
        const w = await writeContractAsync(wc({
          address: ADDRESSES.vault, abi: vaultAbi, functionName: "withdrawTokens", args: [value],
        }));
        log.push(`withdraw: ${w.slice(0, 10)}…`);
      }
      rb(); rt(); rs();
    } catch (e) {
      log.push(`${action} failed: ${(e as Error).message.split("\n")[0]}`);
    }
  };

  return (
    <>
      <h2>4. Vault</h2>
      <section>
        <article>
          <h3>Actions</h3>
          <label><span>Action</span>
            <select value={action} onChange={(e) => setAction(e.target.value as Action)}>
              <option value="deposit">Deposit CUSD</option>
              <option value="withdraw">Withdraw shares</option>
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
            <dt>Vault CUSD Balance:</dt><dd>{fmt(vaultBal)}</dd>
            <dt>Total Shares:</dt><dd>{fmt(total)}</dd>
            <dt>Your Shares:</dt><dd>{fmt(shares)}</dd>
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
