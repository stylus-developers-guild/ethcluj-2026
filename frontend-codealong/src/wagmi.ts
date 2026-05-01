import { createConfig, http } from 'wagmi'
import { mainnet, sepolia } from 'wagmi/chains'

/*
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
*/

// Replace with superposition
export const config = createConfig({
  chains: [mainnet, sepolia],
  transports: {
    [mainnet.id]: http(),
    [sepolia.id]: http(),
  },
})

declare module 'wagmi' {
  interface Register {
    config: typeof config
  }
}
