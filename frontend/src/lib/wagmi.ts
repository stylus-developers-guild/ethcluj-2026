/**
 * Wagmi config — the single source of truth for "which chains and how do we
 * talk to them" in the entire app.
 *
 * Why each piece:
 *  - `chains`     : the list of networks the user is allowed to use.
 *  - `transports` : how wagmi/viem actually sends RPC calls. `http()` with no
 *                   argument uses the chain's default public RPC; in production
 *                   you'd pass `http("https://your-private-rpc...")`.
 *  - `connectors` : wallet adapters. `injected()` covers MetaMask, Rabby, and
 *                   any other EIP-1193 wallet that injects `window.ethereum`.
 *
 * The TypeScript `declare module` block teaches wagmi's hooks that THIS config
 * is the active one, so `useReadContract` etc. infer the chain id correctly.
 */
import { http, createConfig } from "wagmi";
import { arbitrumSepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [arbitrumSepolia],
  connectors: [injected()],
  transports: { [arbitrumSepolia.id]: http() },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
