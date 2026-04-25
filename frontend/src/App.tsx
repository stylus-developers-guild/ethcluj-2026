import {
  useConnect,
  useConnection,
  useConnectors,
  useDisconnect,
  useSwitchChain,
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  type BaseError,
} from "wagmi";
import { superPosition } from "./wagmi";
import { wethAbi } from "./abis/weth";
import { formatUnits, parseEther } from "viem";

const WETH_ADDRESS = "0x22b9fa698b68bBA071B513959794E9a47d19214c" as const;

function MintWeth() {
  const { data: hash, isPending, writeContract, error } = useWriteContract();
  async function submit(e: React.SubmitEvent<HTMLFormElement>) {
    e.preventDefault();
    const formData = new FormData(e.target as HTMLFormElement);
    const amountToMint = formData.get("amountToMint") as string;
    writeContract({
      address: WETH_ADDRESS,
      abi: wethAbi,
      functionName: "deposit",
      value: parseEther(amountToMint),
    });
  }

  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({ hash });

  return (
    <>
      <p>Mint WSPN!!!</p>
      <form onSubmit={submit}>
        <label htmlFor="amountToMint">Amount</label>
        <input
          type="number"
          step="0.001"
          id="amountToMint"
          name="amountToMint"
        />
        <button type="submit" disabled={isPending}>
          {isPending ? "Confirming..." : "Mint!"}
        </button>
        {hash && <div>Transaction Hash: {hash}</div>}
        {isConfirming && <div>Waiting for confirmation...</div>}
        {isConfirmed && <div>Transaction confirmed.</div>}
        {error && (
          <div>
            {" "}
            Error: {(error as BaseError).shortMessage || error.message}{" "}
          </div>
        )}
      </form>
    </>
  );
}


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

  const userAddress = connection.addresses?.[0];

  const { data: userBalanceOfWeth } = useReadContract({
    address: WETH_ADDRESS,
    abi: wethAbi,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress
    }
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
            type="button"
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
          >
            {connector.name}
          </button>
        ))}
        <div>{status}</div>
        <div>{error?.message}</div>
      </div>
      <div>
        {totalSupply !== undefined && decimals !== undefined ? (
          <p>Current total supply is {formatUnits(totalSupply, decimals)}</p>
        ) : (
          <p>Could not get weth price</p>
        )}
        <MintWeth />
        {connection.status === "connected" && (
          <p>Balance of WSPN: {userBalanceOfWeth}</p>
        )}
      </div>
    </>
  );
}

export default App;
