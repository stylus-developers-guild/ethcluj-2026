import { createConfig, http, injected } from "wagmi";
import { defineChain } from "viem";

export const superPosition = defineChain({
  id: 98985,
  name: "Super Position Testnet",
  nativeCurrency: {
    name: "Super Position",
    symbol: "SPN",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ["https://testnet-rpc.superposition.so"],
    },
  },
  blockExplorers: {
    default: {
      name: "Blockscout",
      url: "https://testnet-explorer.superposition.so/",
    },
  },
});

export const config = createConfig({
  chains: [superPosition],
  connectors: [injected()],
  transports: {
    [superPosition.id]: http(),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
