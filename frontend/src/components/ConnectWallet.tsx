/**
 * Wallet connect / disconnect button.
 *
 * Three wagmi hooks at play:
 *  - useAccount()    → address + connection status of the active wallet.
 *  - useConnect()    → list of available connectors + a `connect()` action.
 *  - useDisconnect() → tears down the session.
 *
 * `connectors[0]` is our injected connector (defined in src/lib/wagmi.ts).
 * In a multi-wallet app you'd render one button per connector.
 */
import { useAccount, useChainId, useConnect, useDisconnect } from "wagmi";

const short = (a?: string) => (a ? `${a.slice(0, 6)}…${a.slice(-4)}` : "");

export default function ConnectWallet() {
  const { address, isConnected } = useAccount();
  const { connect, connectors, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const chainId = useChainId();

  return (
    <nav>
      <span>{isConnected ? short(address) : "Not connected"}</span>
      {isConnected ? (
        <button onClick={() => disconnect()}>Disconnect</button>
      ) : (
        <button onClick={() => connect({ connector: connectors[0] })} disabled={isPending}>
          Connect Wallet
        </button>
      )}
      <span>Network: {chainId === 421614 ? "Arbitrum Sepolia" : `Chain ${chainId}`}</span>
    </nav>
  );
}
