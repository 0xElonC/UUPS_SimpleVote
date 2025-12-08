# ZK 投票电路说明

## 电路概述

`vote.circom` 实现了一个零知识投票证明系统，允许投票者：
- ✅ 证明自己有资格投票
- ✅ 证明投票选项合法
- ❌ **不泄露**投票者身份
- ❌ **不泄露**投票选择

## 输入输出

### 私有输入（Witness）
| 输入 | 类型 | 说明 |
|------|------|------|
| `voterAddress` | uint256 | 投票者的以太坊地址（转换为数字） |
| `voterOption` | uint256 | 投票选项 (1, 2, 3...) |
| `secret` | uint256 | 随机盐值（防止暴力破解 commitment） |

### 公开输入（Public Inputs）
| 输入 | 类型 | 说明 |
|------|------|------|
| `proposalId` | uint256 | 提案 ID |
| `optionCount` | uint256 | 该提案的选项总数 |
| `nullifierHash` | uint256 | Poseidon(voterAddress, proposalId) |
| `voteCommitment` | uint256 | Poseidon(voterAddress, voterOption, secret) |

## 约束逻辑

### 约束 1：验证 nullifierHash
```
nullifierHash = Poseidon(voterAddress, proposalId)
```
- **目的**：防止重复投票
- **原理**：每个地址在每个提案中只有一个唯一的 nullifier
- **隐私**：无法从 nullifierHash 反推 voterAddress

### 约束 2：验证 voteCommitment
```
voteCommitment = Poseidon(voterAddress, voterOption, secret)
```
- **目的**：隐藏投票选择
- **原理**：使用随机盐值，即使同一选项的 commitment 也不同
- **隐私**：无法从 voteCommitment 反推 voterOption

### 约束 3：验证选项合法性
```
1 <= voterOption <= optionCount
```
- **目的**：防止无效投票
- **原理**：使用比较电路强制范围检查
- **安全**：即使私有输入，也必须满足范围约束

## 编译步骤

### 1. 安装依赖

```bash
# 安装 Circom 编译器
curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh
git clone https://github.com/iden3/circom.git
cd circom
cargo build --release
cargo install --path circom
cd ..

# 安装 snarkjs
npm install -g snarkjs

# 安装 circomlib
npm install --save-dev circomlib
```

### 2. 编译电路

```bash
cd circuits
circom vote.circom --r1cs --wasm --sym -o ../zkp
```

输出文件：
- `zkp/vote.r1cs` - 约束系统
- `zkp/vote_js/vote.wasm` - Witness 计算程序
- `zkp/vote.sym` - 符号表

### 3. 查看电路信息

```bash
snarkjs r1cs info zkp/vote.r1cs
```

预期输出（约束数量）：
- Poseidon(2): ~153 约束
- Poseidon(3): ~229 约束
- GreaterThan(252): ~252 约束
- LessEqThan(252): ~252 约束
- **总计**：~886 约束

## 电路大小分析

| 组件 | 约束数 | 占比 |
|------|--------|------|
| nullifierHash (Poseidon-2) | 153 | 17% |
| voteCommitment (Poseidon-3) | 229 | 26% |
| 范围检查（两个比较器） | 504 | 57% |
| **总计** | ~886 | 100% |

**优化建议：**
- 使用 `Num2Bits` + `LessThan` 可能更高效
- 考虑使用 Plonk（约束更灵活）

## 安全考虑

### ✅ 防护措施
1. **防重复投票**：nullifier 机制
2. **防暴力破解**：secret 盐值（256 位）
3. **范围检查**：强制 voterOption 合法性

### ⚠️ 注意事项
1. **address 转换**：以太坊地址需要转换为 uint256
2. **有限域溢出**：确保所有输入 < 素数域 p
3. **可信设置**：Groth16 需要 Trusted Setup

## 下一步

1. **Powers of Tau**：准备通用可信设置
2. **Phase 2 Setup**：为此电路生成 zkey
3. **生成验证器**：导出 Solidity 验证合约
4. **前端集成**：使用 snarkjs 生成证明

参考文档：
- [Circom 官方文档](https://docs.circom.io/)
- [snarkjs 使用指南](https://github.com/iden3/snarkjs)
- [Poseidon 哈希](https://www.poseidon-hash.info/)
