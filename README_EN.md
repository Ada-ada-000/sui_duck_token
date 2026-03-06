# DUCK Protocol (Sui Move)

English version of deployment and usage guide for the DUCK Protocol demo on Sui Testnet.

## Overview

This project contains 3 Move modules:

- `duck_token::duck_token`: DUCK token (9 decimals)
- `duck_vault::duck_vault`: personal vault (deposit / withdraw / balance)
- `duck_lending::duck_lending`: lending pool (50% LTV, pledge / borrow / repay / query)

## Fixed Parameters

- Symbol: `DUCK`
- Name: `Decentral Universal Credit Kernel`
- Description: `Decentralized universal credit kernel, on-chain credit, cross-chain settlement.`
- Decimals: `9`
- LTV: `50%`
- Currency Init Standard: `coin_registry::new_currency_with_otw`
- Error codes:
  - `E_NO_LOAN = 1001`
  - `E_INSUFFICIENT_COLLATERAL = 1002`
  - `E_LTV_RATIO_ERROR = 1003`
  - `E_OUTSTANDING_DEBT = 1004`

## Testnet Deployment (Verified)

- Network: `Sui Testnet`
- Publisher: `0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179`
- Package ID: `0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35`
- TreasuryCap<DUCK_TOKEN>: `0xa795238edf6bae8baea21a32600fa203b0d8b9b8e83eaf5428733bb5850f6951`
- CoinMetadata<DUCK_TOKEN>: `0xb4fea490ec15f1a11addfcc664f2e7c1fd291f19dcf4284beaacb9d8eda0a301`
- DuckLending (shared): `0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747`
- Example DuckVault (owned): `0x159fa941b082cbef70fbe0258364a39a2efb40ad3d107894ab3eddc7b635b1ac`

## Build

```bash
sui move build
sui move test
```

## Publish

```bash
sui client switch --env testnet
sui client publish --gas-budget 100000000
```

## Key Calls

### Mint

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_token \
  --function mint \
  --args 0xa795238edf6bae8baea21a32600fa203b0d8b9b8e83eaf5428733bb5850f6951 1000000000 0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179 \
  --gas-budget 100000000
```

### Pledge

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function pledge \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <DUCK_COIN_ID> \
  --gas-budget 100000000
```

### Borrow

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function borrow \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 500000000 \
  --gas-budget 100000000
```

### Repay

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function repay \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <DUCK_COIN_ID> \
  --gas-budget 100000000
```

### Query Loan

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function get_loan_info \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179 \
  --gas-budget 100000000
```

### Redeem Collateral (debt must be 0)

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function redeem \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 500000000 \
  --gas-budget 100000000
```
