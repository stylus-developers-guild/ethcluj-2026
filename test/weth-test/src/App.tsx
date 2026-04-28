import { superPosition } from "./wagmi";
import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useSwitchChain,
  useReadContract,
  useWriteContract
} from "wagmi";
import wethAbi

function App() {
  const connection = useConnection();
  const { mutate: switchChain } = useSwitchChain();
  const { connect, status, error } = useConnect();
  const connectors = useConnectors();
  const { disconnect } = useDisconnect();

  const { data: totalSupply } = useReadContract({
    address: WETH_ADDRESS,
    abi: wethAbi,
    functionName: "totalSupply",
  });

  const { data: decimals } = useReadContract({
    address: WETH_ADDRESS,
    abi: wethAbi,
    functionName: "decimals",
  });



  return (
    <>
      <div>
        <h2>Connection</h2>

        <div>
          status: {connection.status}
          <br />
          addresses: {JSON.stringify(connection.addresses)}
          <br />
          chainId: {connection.chainId}
        </div>

        {connection.status === "connected" && (
          <button type="button" onClick={() => disconnect()}>
            Disconnect
          </button>
        )}
      </div>

      <div>
        <h2>Connect</h2>
        {connectors.map((connector) => (
          <button
            key={connector.uid}
            onClick={() =>
              connect(
                { connector },
                {
                  onSuccess: () => {
                    switchChain({ chainId: superPosition.id });
                  },
                },
              )
            }
            type="button"
          >
            {connector.name}
          </button>
        ))}
        <div>{status}</div>
        <div>{error?.message}</div>
      </div>
    </>
  );
}

export default App;
