/**
 * App shell — wires up the two providers wagmi requires:
 *
 *   <WagmiProvider>          ← provides chain config + connectors
 *     <QueryClientProvider>  ← wagmi caches reads/writes via TanStack Query
 *       ...your app
 *
 * Order matters: WagmiProvider MUST wrap QueryClientProvider, because every
 * wagmi hook internally calls `useQueryClient()`.
 */
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider } from "wagmi";
import Index from "./pages/Index";
import { config } from "./lib/wagmi";

const queryClient = new QueryClient();

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <Index />
      </QueryClientProvider>
    </WagmiProvider>
  );
}
