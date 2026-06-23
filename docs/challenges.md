# Stylus Challenges

These challenges are designed to test your understanding of the Stylus smart contract
concepts covered in Chapter 3. Each challenge is a partially implemented Rust contract
that you need to complete. The source code for each challenge (and solutions) is available
in the repository under `stylus-challenges/` and `stylus-challenges-solved/`.

```{note}
The contract code in these challenges was not written with ERC20 safety in mind.
There are no return value checks. **Not for production!**
```

## Challenge 1: Vault

This is a simple ERC-20 token vault. Users can deposit tokens and receive shares
proportional to their deposit. Later they can burn their shares to withdraw the
underlying tokens. Your job is to implement the `deposit` and `withdraw` functions.

The vault uses a share-based accounting system: when you deposit tokens, you receive
shares based on the ratio of your deposit to the total assets in the vault. When you
withdraw, you burn shares and receive tokens proportional to your share of the vault.

**Key concepts tested:**

- `sol_interface!` for calling external ERC-20 contracts
- Storage maps and arithmetic with `U256`
- Custom Solidity errors via `sol!` and `SolidityError`

## Challenge 2: Paid Email

This is a paid email service where recipients stipulate an amount of a token they
must receive to accept email. Senders must pay that amount to add their CID email
content to the queue.

The DID content should be encrypted to the recipient's public key to avoid revealing
the content.

**Key concepts tested:**

- Complex storage layouts with nested maps and vectors
- Timestamp-based logic and refund windows
- Multi-token support via `sol_interface!`
- Epoch-based time tracking

## Challenge 3: Lending

A simple single-asset lending protocol. Users can supply collateral, borrow against it,
and repay with interest. The protocol tracks borrow positions using tickets and
time-weighted interest accumulation.

**Key concepts tested:**

- Interest rate calculations with timepoints
- Collateral requirements and liquidation logic
- Ticket-based position tracking
- Macro usage for assertion patterns (`assert_or!`)

```{tip}
Start with Challenge 1 (Vault) as it is the simplest. Each challenge builds on
concepts from the previous one. If you get stuck, the solved versions are in the
`stylus-challenges-solved/` directory.
```
