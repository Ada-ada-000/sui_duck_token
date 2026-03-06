# DUCK Protocol (Sui Move)

English version: [README_EN.md](README_EN.md)

DUCK Protocol 是一个在 Sui 测试网运行的去中心化通用信用内核示例，包含三个 Move 模块：

- `duck_token::duck_token`：DUCK 代币（9 位精度）
- `duck_vault::duck_vault`：个人金库（存款/取款/余额查询）
- `duck_lending::duck_lending`：借贷池（可配置 LTV，抵押/借款/还款/赎回/清算/风控开关）

## 1. 合约参数

- Symbol: `DUCK`
- Name: `Decentral Universal Credit Kernel`
- Description: `Decentralized universal credit kernel, on-chain credit, cross-chain settlement.`
- Decimals: `9`
- Default Borrow LTV: `50% (5000 bps)`
- Default Liquidation Threshold: `70% (7000 bps)`
- Default Liquidation Bonus: `5% (500 bps)`
- Currency Init Standard: `coin_registry::new_currency_with_otw`
- Error Codes:
  - `E_NO_LOAN = 1001`
  - `E_INSUFFICIENT_COLLATERAL = 1002`
  - `E_LTV_RATIO_ERROR = 1003`
  - `E_OUTSTANDING_DEBT = 1004`
  - `E_PROTOCOL_PAUSED = 1005`
  - `E_NOT_ADMIN = 1006`
  - `E_BAD_RISK_PARAMS = 1007`
  - `E_POSITION_HEALTHY = 1008`
  - `E_INVALID_AMOUNT = 1009`

## 2. 测试网部署信息（已验证）

- Network: `Sui Testnet`
- Publisher Address: `0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179`
- Package ID: `0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35`
- TreasuryCap<DUCK_TOKEN>: `0xa795238edf6bae8baea21a32600fa203b0d8b9b8e83eaf5428733bb5850f6951`
- CoinMetadata<DUCK_TOKEN>: `0xb4fea490ec15f1a11addfcc664f2e7c1fd291f19dcf4284beaacb9d8eda0a301`
- DuckLending (shared): `0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747`
- Example DuckVault (owned): `0x159fa941b082cbef70fbe0258364a39a2efb40ad3d107894ab3eddc7b635b1ac`

## 3. 目录结构

- `Move.toml`
- `sources/duck_token.move`
- `sources/duck_vault.move`
- `sources/duck_lending.move`

## 4. 本地编译

```bash
sui move build
sui move test
```

## 5. 发布到测试网

> 首次使用请先初始化 `sui client` 并导入私钥。

```bash
sui client switch --env testnet
sui client switch --address 0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179
sui client publish --gas-budget 100000000
```

## 6. 交互命令（可直接改参数复用）

### 6.1 创建借贷池

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function create_pool \
  --gas-budget 100000000
```

### 6.2 创建个人金库

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_vault \
  --function create_vault \
  --gas-budget 100000000
```

### 6.3 铸币（示例：1 DUCK = 1_000_000_000）

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_token \
  --function mint \
  --args 0xa795238edf6bae8baea21a32600fa203b0d8b9b8e83eaf5428733bb5850f6951 1000000000 0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179 \
  --gas-budget 100000000
```

### 6.4 抵押到借贷池

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function pledge \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <DUCK_COIN_ID> \
  --gas-budget 100000000
```

### 6.5 借款（示例：0.5 DUCK）

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function borrow \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 500000000 \
  --gas-budget 100000000
```

### 6.6 还款

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function repay \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <DUCK_COIN_ID> \
  --gas-budget 100000000
```

### 6.7 查询借贷信息

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function get_loan_info \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 0x4509239f59360d7b7bf7dc296418c115d90226b0a16f010dbebe8d217c65e179 \
  --gas-budget 100000000
```

### 6.8 赎回抵押（需先还清 debt）

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function redeem \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 500000000 \
  --gas-budget 100000000
```

### 6.9 调整风控参数（仅 AdminCap 持有者）

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function set_risk_params \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <RISK_ADMIN_CAP_ID> 5000 7000 500 \
  --gas-budget 100000000
```

### 6.10 清算不健康仓位

```bash
sui client call \
  --package 0xddb18dd3e10385e899e957508d2ceab971b18e9d16da63903ee9052283d57c35 \
  --module duck_lending \
  --function liquidate \
  --args 0x7dcd9eb4ea030820f680baa53afe5a979fd6a7c472e2ca22e74df458b6363747 <BORROWER_ADDRESS> <DUCK_COIN_ID_FOR_REPAY> \
  --gas-budget 100000000
```

## 7. GitHub

- Repository: https://github.com/Ada-ada-000/sui_duck_token.git

## 8. 风险边界（面试说明）

- 当前实现是教学/演示版借贷协议，已包含基础清算与风险参数治理，但仍不包含预言机、利息模型和坏账拍卖处理。
- 价格假设为固定计价（DUCK 抵押 DUCK），用于展示 Move 资产流、清算和状态约束，不代表生产级金融风控。
- `borrow/repay/redeem` 与 `vault` 流程中的 `self_transfer` 是刻意的 UX 选择：直接把结果资产转给交易发起者，便于前端集成；如需更高可组合性，可改成返回 `Coin<T>` 由调用方继续编排。
