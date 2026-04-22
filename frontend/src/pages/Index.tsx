/**
 * Single-page UI for the EthCluj 2026 Solidity challenges.
 * Layout uses semantic HTML only — no <div>s.
 */
import ConnectWallet from "@/components/ConnectWallet";
import WethMinting from "@/components/challenges/WethMinting";
import StablecoinManager from "@/components/challenges/StablecoinManager";
import Dex from "@/components/challenges/Dex";
import Vault from "@/components/challenges/Vault";
import FlashLoan from "@/components/challenges/FlashLoan";

export default function Index() {
  return (
    <main>
      <header>
        <a
          href="/ethcluj-2026/"
          className="inline-flex items-center gap-2 hover:opacity-80"
        >
          <h1 className="text-4xl font-bold">Arbitrum Workshop</h1>
        </a>
        <ConnectWallet />
      </header>
      <WethMinting />        <hr />
      <StablecoinManager />  <hr />
      <Dex />                <hr />
      <Vault />              <hr />
      <FlashLoan />
    </main>
  );
}
