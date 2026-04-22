/**
 * Contract addresses & ABIs for the EthCluj 2026 Solidity Challenges.
 *
 * --- Why this file exists ---------------------------------------------------
 * wagmi/viem are *typesafe*: if you give them an ABI as a `const` literal,
 * every `useReadContract` / `useWriteContract` call gets fully-typed arguments
 * and return values inferred from the Solidity signatures.
 *
 * That's why each ABI below ends with `as const` — without it TypeScript would
 * widen the literal types ("function" → string) and we'd lose the inference.
 *
 * --- Why minimal ABIs -------------------------------------------------------
 * An ABI only needs to contain the functions/events your dapp actually calls.
 * Smaller ABIs = smaller bundle + clearer intent for a workshop reader.
 *
 * Source contract:
 *   https://github.com/stylus-developers-guild/ethcluj-2026/blob/trunk/solidity-challenges-solved/4_FlashLoan.sol
 */

import type { Address } from "viem";

// ---- Deployment addresses --------------------------------------------------
// Swap these with the addresses you deployed to (Arbitrum Sepolia by default).
// Using Vite env vars (`VITE_*`) lets you change networks without recompiling.
export const ADDRESSES = {
  weth:          (import.meta.env.VITE_WETH_ADDRESS          ?? "0x0000000000000000000000000000000000000000") as Address,
  cusd:          (import.meta.env.VITE_CUSD_ADDRESS          ?? "0x0000000000000000000000000000000000000000") as Address,
  manager:       (import.meta.env.VITE_MANAGER_ADDRESS       ?? "0x0000000000000000000000000000000000000000") as Address,
  dex:           (import.meta.env.VITE_DEX_ADDRESS           ?? "0x0000000000000000000000000000000000000000") as Address,
  vault:         (import.meta.env.VITE_VAULT_ADDRESS         ?? "0x0000000000000000000000000000000000000000") as Address,
  flashBorrower: (import.meta.env.VITE_FLASH_BORROWER_ADDRESS ?? "0x0000000000000000000000000000000000000000") as Address,
} as const;

// ---- ERC20 (used for both WETH and CUSD) -----------------------------------
// `balanceOf` + `approve` are the bread and butter of every dapp.
// `mint(to, amount)` is only present on the *mock* WETH used in this workshop —
// real WETH would expose `deposit()` payable instead.
export const erc20Abi = [
  { type: "function", name: "balanceOf", stateMutability: "view",       inputs: [{ name: "owner", type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve",   stateMutability: "nonpayable", inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "mint",      stateMutability: "nonpayable", inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], outputs: [] },
  { type: "event",    name: "Transfer",  inputs: [{ indexed: true, name: "from", type: "address" }, { indexed: true, name: "to", type: "address" }, { indexed: false, name: "value", type: "uint256" }] },
] as const;

// ---- Manager (CDP-style stablecoin: deposit WETH → mint CUSD) --------------
export const managerAbi = [
  { type: "function", name: "MIN_COLLAT_RATIO",  stateMutability: "view",       inputs: [],                              outputs: [{ type: "uint256" }] },
  { type: "function", name: "depositAmountOf",   stateMutability: "view",       inputs: [{ type: "address" }],           outputs: [{ type: "uint256" }] },
  { type: "function", name: "mintedAmountOf",    stateMutability: "view",       inputs: [{ type: "address" }],           outputs: [{ type: "uint256" }] },
  { type: "function", name: "collatRatio",       stateMutability: "view",       inputs: [{ type: "address" }],           outputs: [{ type: "uint256" }] },
  { type: "function", name: "deposit",           stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "withdraw",          stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "mint",              stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "burn",              stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
] as const;

// ---- DEX (constant-product AMM: token1 = CUSD, token2 = WETH) --------------
export const dexAbi = [
  { type: "function", name: "reserve1",           stateMutability: "view",       inputs: [],                                       outputs: [{ type: "uint256" }] },
  { type: "function", name: "reserve2",           stateMutability: "view",       inputs: [],                                       outputs: [{ type: "uint256" }] },
  { type: "function", name: "swapToken1ForToken2", stateMutability: "nonpayable", inputs: [{ name: "amountIn", type: "uint256" }], outputs: [] },
  { type: "function", name: "swapToken2ForToken1", stateMutability: "nonpayable", inputs: [{ name: "amountIn", type: "uint256" }], outputs: [] },
  { type: "event",    name: "Swap",               inputs: [{ indexed: false, name: "sender", type: "address" }, { indexed: false, name: "amountIn", type: "uint256" }, { indexed: false, name: "amountOut", type: "uint256" }] },
] as const;

// ---- TokenVault (CUSD lending pool with flash loans) -----------------------
export const vaultAbi = [
  { type: "function", name: "totalShares",    stateMutability: "view",       inputs: [],                              outputs: [{ type: "uint256" }] },
  { type: "function", name: "sharesOf",       stateMutability: "view",       inputs: [{ type: "address" }],           outputs: [{ type: "uint256" }] },
  { type: "function", name: "depositTokens",  stateMutability: "nonpayable", inputs: [{ name: "amount", type: "uint256" }], outputs: [] },
  { type: "function", name: "withdrawTokens", stateMutability: "nonpayable", inputs: [{ name: "shares", type: "uint256" }], outputs: [] },
  { type: "function", name: "flashLoan",      stateMutability: "nonpayable", inputs: [{ name: "borrower", type: "address" }, { name: "amount", type: "uint256" }, { name: "data", type: "bytes" }], outputs: [] },
] as const;
