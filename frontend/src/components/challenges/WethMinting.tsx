/**
 * Challenge 1 — WETH minting.
 *
 * Goal: get test WETH into the connected wallet so we can play with the rest
 * of the system.
 *
 * Two wagmi hooks are introduced here:
 *
 *   useReadContract({ address, abi, functionName, args })
 *     → calls a `view`/`pure` Solidity function. Returns cached `data`.
 *     → We pass `query: { enabled: !!address }` so the read is *skipped*
 *       while no wallet is connected (avoids spamming RPC with calls that
 *       would need an `args` we don't have yet).
 *
 *   useWriteContract()
 *     → returns `writeContractAsync(...)` which sends a state-changing tx.
 *       Using the *async* variant (vs `writeContract`) lets us `await` the
 *       tx hash and chain follow-up logic — essential later for approve-then-act.
 */
import { useState } from "react";
import { useAccount, useReadContract, useWriteContract } from "wagmi";
import { ADDRESSES, erc20Abi } from "@/lib/contracts";
import { fmt, safeParse, useEventLog, wc } from "@/lib/utils-eth";

export default function WethMinting() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const log = useEventLog();

  // READ — current WETH balance of the connected user.
  const { data: balance, refetch } = useReadContract({
    address: ADDRESSES.weth,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: { enabled: !!address },
  });

  // WRITE — mock WETH exposes `mint(to, amount)` for testing.
  const { writeContractAsync, isPending } = useWriteContract();

  const onMint = async () => {
    if (!address) return;
    try {
      const hash = await writeContractAsync(wc({
        address: ADDRESSES.weth,
        abi: erc20Abi,
        functionName: "mint",
        // `safeParse` converts "1.5" → 1500000000000000000n (18 decimals).
        args: [address, safeParse(amount)],
      }));
      log.push(`mint tx: ${hash.slice(0, 10)}…`);
      refetch(); // pull the new balance after the wallet broadcasts.
    } catch (e) {
      log.push(`mint failed: ${(e as Error).message.split("\n")[0]}`);
    }
  };

  return (
    <>
      <h2>1. WETH Minting</h2>
      <section>
        <article>
          <h3>Actions</h3>
          <label><span>Amount</span>
            <input type="number" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
          <button onClick={onMint} disabled={!address || isPending}>Mint WETH</button>
        </article>
        <article>
          <h3>State</h3>
          <dl><dt>Your WETH Balance:</dt><dd>{fmt(balance)}</dd></dl>
        </article>
        <article>
          <h3>Events / Logs</h3>
          <output>{log.lines.join("\n") || "No events yet..."}</output>
        </article>
      </section>
    </>
  );
}
