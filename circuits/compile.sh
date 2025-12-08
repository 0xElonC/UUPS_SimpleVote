#!/bin/bash

# ZK 投票电路编译脚本
# 用途：编译 vote.circom 并生成所有必要的 ZK 文件

set -e  # 遇到错误立即退出

CIRCUIT_NAME="vote"
BUILD_DIR="../zkp"
PTAU_FILE="powersOfTau28_hez_final_12.ptau"  # 支持 2^12 = 4096 约束
PTAU_URL="https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_12.ptau"

echo "🔧 开始编译 ZK 投票电路..."
echo ""

# 步骤 1: 检查 Circom 是否安装
if ! command -v circom &> /dev/null; then
    echo "❌ Circom 未安装，请先安装 Circom："
    echo "   参考: https://docs.circom.io/getting-started/installation/"
    exit 1
fi
echo "✅ Circom 已安装: $(circom --version)"

# 步骤 2: 检查 snarkjs 是否安装
if ! command -v snarkjs &> /dev/null; then
    echo "❌ snarkjs 未安装，正在安装..."
    npm install -g snarkjs
fi
echo "✅ snarkjs 已安装"

# 步骤 3: 检查 circomlib 是否安装
if [ ! -d "../node_modules/circomlib" ]; then
    echo "⚠️  circomlib 未找到，正在安装..."
    cd ..
    npm install --save-dev circomlib
    cd circuits
fi
echo "✅ circomlib 已安装"

# 步骤 4: 创建输出目录
mkdir -p "$BUILD_DIR"
echo "✅ 创建输出目录: $BUILD_DIR"
echo ""

# 步骤 5: 编译电路
echo "📦 编译电路: $CIRCUIT_NAME.circom"
circom "$CIRCUIT_NAME.circom" \
    --r1cs \
    --wasm \
    --sym \
    --c \
    -o "$BUILD_DIR"

echo "✅ 电路编译完成！"
echo ""

# 步骤 6: 显示电路信息
echo "📊 电路统计信息："
snarkjs r1cs info "$BUILD_DIR/$CIRCUIT_NAME.r1cs"
echo ""

# 步骤 7: 下载 Powers of Tau（如果不存在）
if [ ! -f "$BUILD_DIR/$PTAU_FILE" ]; then
    echo "⬇️  下载 Powers of Tau（约 8MB）..."
    wget -q --show-progress -O "$BUILD_DIR/$PTAU_FILE" "$PTAU_URL"
    echo "✅ Powers of Tau 下载完成"
else
    echo "✅ Powers of Tau 已存在"
fi
echo ""

# 步骤 8: Groth16 Setup (Phase 2)
echo "🔐 执行 Groth16 Setup (Phase 2)..."
snarkjs groth16 setup \
    "$BUILD_DIR/$CIRCUIT_NAME.r1cs" \
    "$BUILD_DIR/$PTAU_FILE" \
    "$BUILD_DIR/${CIRCUIT_NAME}_0000.zkey"
echo "✅ Groth16 Setup 完成"
echo ""

# 步骤 9: 贡献随机性
echo "🎲 贡献随机性..."
snarkjs zkey contribute \
    "$BUILD_DIR/${CIRCUIT_NAME}_0000.zkey" \
    "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" \
    --name="First contribution" \
    -v \
    -e="$(date +%s)$(openssl rand -hex 32)"
echo "✅ 随机性贡献完成"
echo ""

# 步骤 10: 导出 Verification Key
echo "🔑 导出 Verification Key..."
snarkjs zkey export verificationkey \
    "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" \
    "$BUILD_DIR/verification_key.json"
echo "✅ Verification Key 导出完成"
echo ""

# 步骤 11: 生成 Solidity 验证器合约
echo "📄 生成 Solidity 验证器合约..."
snarkjs zkey export solidityverifier \
    "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" \
    "../contracts/VoteVerifier.sol"
echo "✅ VoteVerifier.sol 生成成功！"
echo ""

# 步骤 12: 生成测试证明（验证电路正确性）
echo "🧪 生成测试证明..."
cat > "$BUILD_DIR/test_input.json" << EOF
{
    "voterAddress": "1234567890",
    "voterOption": "2",
    "secret": "9876543210",
    "proposalId": "1",
    "optionCount": "3",
    "nullifierHash": "0",
    "voteCommitment": "0"
}
EOF

# 计算正确的公开输入
node << 'NODESCRIPT'
const fs = require('fs');
const buildPoseidon = require('circomlibjs').buildPoseidon;

(async () => {
    const poseidon = await buildPoseidon();
    const F = poseidon.F;

    const voterAddress = BigInt("1234567890");
    const voterOption = BigInt("2");
    const secret = BigInt("9876543210");
    const proposalId = BigInt("1");

    // 计算 nullifierHash
    const nullifierHash = poseidon([voterAddress, proposalId]);

    // 计算 voteCommitment
    const voteCommitment = poseidon([voterAddress, voterOption, secret]);

    const input = {
        voterAddress: voterAddress.toString(),
        voterOption: voterOption.toString(),
        secret: secret.toString(),
        proposalId: proposalId.toString(),
        optionCount: "3",
        nullifierHash: F.toString(nullifierHash),
        voteCommitment: F.toString(voteCommitment)
    };

    fs.writeFileSync('../zkp/test_input.json', JSON.stringify(input, null, 2));
    console.log('✅ 测试输入已更新');
})();
NODESCRIPT

snarkjs groth16 fullprove \
    "$BUILD_DIR/test_input.json" \
    "$BUILD_DIR/${CIRCUIT_NAME}_js/${CIRCUIT_NAME}.wasm" \
    "$BUILD_DIR/${CIRCUIT_NAME}_final.zkey" \
    "$BUILD_DIR/test_proof.json" \
    "$BUILD_DIR/test_public.json"

echo "✅ 测试证明生成成功！"
echo ""

# 步骤 13: 验证测试证明
echo "🔍 验证测试证明..."
snarkjs groth16 verify \
    "$BUILD_DIR/verification_key.json" \
    "$BUILD_DIR/test_public.json" \
    "$BUILD_DIR/test_proof.json"

echo ""
echo "🎉 所有步骤完成！"
echo ""
echo "📁 生成的文件："
echo "   - zkp/vote.r1cs              (约束系统)"
echo "   - zkp/vote_js/vote.wasm      (Witness 计算)"
echo "   - zkp/vote_final.zkey        (Proving Key - 前端使用)"
echo "   - zkp/verification_key.json  (Verification Key)"
echo "   - contracts/VoteVerifier.sol (Solidity 验证器)"
echo ""
echo "下一步："
echo "1. 部署 VoteVerifier.sol 到 Sepolia"
echo "2. 复制 vote.wasm 和 vote_final.zkey 到前端 public/circuits/"
echo "3. 在前端使用 snarkjs 生成证明"
