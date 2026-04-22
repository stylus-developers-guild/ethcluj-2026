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
        <h1>Arbitrum Workshop</h1>
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
