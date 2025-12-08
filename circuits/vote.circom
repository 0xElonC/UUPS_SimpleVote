pragma circom 2.0.0;

include "../node_modules/circomlib/circuits/poseidon.circom";
include "../node_modules/circomlib/circuits/comparators.circom";

/**
 * VoteCircuit - 零知识投票电路
 *
 * 证明声明：
 * 1. 我知道一个有效的投票者地址
 * 2. 我的投票选项在有效范围内（1 到 optionCount）
 * 3. 我能正确计算 nullifierHash（防止重复投票）
 * 4. 我能正确计算 voteCommitment（隐藏投票选择）
 */
template VoteCircuit() {
    // ============ 私有输入（证明者秘密）============
    signal input voterAddress;        // 投票人地址（作为 uint256）
    signal input voterOption;         // 投票选项 (1, 2, 3...)
    signal input secret;              // 随机盐值（防止暴力破解）

    // ============ 公开输入（验证者可见）============
    signal input proposalId;          // 提案 ID
    signal input optionCount;         // 选项总数
    signal input nullifierHash;       // 防重复投票标识（公开）
    signal input voteCommitment;      // 选票承诺（公开）

    // ============ 中间信号 ============
    signal nullifierInput[2];
    signal commitmentInput[3];

    // ============ 约束1：验证 nullifierHash ============
    // nullifierHash = Poseidon(voterAddress, proposalId)
    // 这确保每个地址在每个提案中只有一个唯一的 nullifier
    nullifierInput[0] <== voterAddress;
    nullifierInput[1] <== proposalId;

    component nullifierHasher = Poseidon(2);
    nullifierHasher.inputs[0] <== nullifierInput[0];
    nullifierHasher.inputs[1] <== nullifierInput[1];

    // 验证公开输入的 nullifierHash 是否正确
    nullifierHash === nullifierHasher.out;

    // ============ 约束2：验证 voteCommitment（优化）============
    // voteCommitment = Poseidon(nullifierHash, voterOption, secret)
    // 使用 nullifierHash 替代 voterAddress，消除冗余
    commitmentInput[0] <== nullifierHash;
    commitmentInput[1] <== voterOption;
    commitmentInput[2] <== secret;

    component commitmentHasher = Poseidon(3);
    commitmentHasher.inputs[0] <== commitmentInput[0];
    commitmentHasher.inputs[1] <== commitmentInput[1];
    commitmentHasher.inputs[2] <== commitmentInput[2];

    // 验证公开输入的 voteCommitment 是否正确
    voteCommitment === commitmentHasher.out;

    // ============ 约束3：验证投票选项合法性 ============
    // 确保 1 <= voterOption <= optionCount

    // 检查 voterOption > 0
    component greaterThanZero = GreaterThan(252);
    greaterThanZero.in[0] <== voterOption;
    greaterThanZero.in[1] <== 0;
    greaterThanZero.out === 1;

    // 检查 voterOption <= optionCount
    component lessThanOrEqual = LessEqThan(252);
    lessThanOrEqual.in[0] <== voterOption;
    lessThanOrEqual.in[1] <== optionCount;
    lessThanOrEqual.out === 1;
}

// 主组件：指定哪些输入是公开的
component main {public [proposalId, optionCount, nullifierHash, voteCommitment]} = VoteCircuit();
