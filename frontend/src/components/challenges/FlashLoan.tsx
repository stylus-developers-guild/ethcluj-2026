/**
 * Challenge 4b — Flash Loan.
 *
 * `Vault.flashLoan(borrower, amount, data)` does, atomically:
 *   1. transfer `amount` CUSD to the `borrower` contract,
 *   2. call `borrower.onFlashLoan(amount, data)` (the user-defined logic),
 *   3. require the vault's CUSD balance is ≥ what it was before.
 *
 * If step 3 fails the whole tx reverts → no risk to the pool.
 *
 * The `data` field is opaque `bytes` forwarded to the borrower. The sample
 * `FlashBorrower` decodes it as `abi.decode(data, (uint256))` — i.e. the amount
 * to swap on the DEX inside its callback. Pass `0x` if your borrower doesn't
 * need any params.
 */
import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { ADDRESSES, vaultAbi } from "@/lib/contracts";
import { safeParse, useEventLog, wc } from "@/lib/utils-eth";

export default function FlashLoan() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const [data, setData] = useState("0x");
  const log = useEventLog();

  const { writeContractAsync, isPending } = useWriteContract();

  const onRequest = async () => {
    if (!address) return;
    // Force `0x`-prefix so viem accepts it as a `Hex` string.
    const bytes = (data.startsWith("0x") ? data : `0x${data}`) as `0x${string}`;
    try {
      const hash = await writeContractAsync(wc({
        address: ADDRESSES.vault,
        abi: vaultAbi,
        functionName: "flashLoan",
        args: [ADDRESSES.flashBorrower, safeParse(amount), bytes],
      }));
      log.push(`flashLoan tx: ${hash.slice(0, 10)}…`);
    } catch (e) {
      log.push(`flashLoan failed: ${(e as Error).message.split("\n")[0]}`);
    }
  };

  return (
    <>
      <h2>5. Flash Loan (Challenge 4)</h2>
      <section>
        <article>
          <h3>Actions</h3>
          <label><span>Loan Amount (CUSD):</span>
            <input type="number" placeholder="0.0" value={amount} onChange={(e) => setAmount(e.target.value)} />
          </label>
          <label><span>Callback Data (hex):</span>
            <input type="text" placeholder="0x..." value={data} onChange={(e) => setData(e.target.value)} />
          </label>
          <button onClick={onRequest} disabled={!address || isPending}>Request Flash Loan</button>
        </article>
        <article>
          <h3>State</h3>
          <dl><dt>Status:</dt><dd>{isPending ? "Pending" : "Idle"}</dd></dl>
        </article>
        <article>
          <h3>Events / Logs</h3>
          <output>{log.lines.join("\n") || "No events yet..."}</output>
        </article>
      </section>
    </>
  );
}
