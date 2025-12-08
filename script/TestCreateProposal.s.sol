// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVotingV2} from "../src/SimpleVotingV2.sol";

/**
 * @title TestCreateProposal
 * @author Sue
 * @notice 测试脚本 - 创建投票提案并添加选项
 *
 * @dev 测试流程:
 * 1. 连接到已部署的 SimpleVotingV2 代理合约
 * 2. 创建一个新的投票提案
 * 3. 为提案添加多个选项
 * 4. 验证提案创建成功
 * 5. 查询并显示提案详情
 *
 * 使用方法:
 * forge script script/TestCreateProposal.s.sol \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   -vvv
 */
contract TestCreateProposal is Script {
    /// @notice SimpleVotingV2 代理合约地址 (替换为你的实际地址)
    address constant PROXY_ADDRESS = 0xEA22e17ABD5D2fd53dF911Bb21cA861ecdBa2436;

    /// @notice SimpleVotingV2 合约实例
    SimpleVotingV2 public voting;

    /**
     * @notice 测试主函数
     */
    function run() external {
        // 1. 获取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("====================================");
        console.log("Test: Create Proposal");
        console.log("====================================");
        console.log("Testing with account:", deployer);
        console.log("Proxy contract:", PROXY_ADDRESS);
        console.log("");

        // 2. 连接到代理合约
        voting = SimpleVotingV2(PROXY_ADDRESS);

        // 3. 查询当前状态
        console.log("Step 1: Query current state...");
        uint256 currentProposalCount = voting.proposalCount();
        console.log("  Current proposal count:", currentProposalCount);
        console.log("  Contract owner:", voting.owner());
        console.log("");

        // 4. 开始广播交易
        vm.startBroadcast(deployerPrivateKey);

        // 5. 创建新提案
        console.log("Step 2: Creating new proposal...");
        string memory title = "Should we upgrade the protocol?";
        uint256 duration = 7 days;  // 7 天投票期

        uint256 newProposalId = voting.createProposal(title, duration);
        console.log("  Proposal created with ID:", newProposalId);
        console.log("  Title:", title);
        console.log("  Duration:", duration, "seconds (7 days)");
        console.log("");

        // 6. 添加选项
        console.log("Step 3: Adding voting options...");

        voting.addOption(newProposalId, "Yes - Upgrade immediately");
        console.log("  Option 1 added: Yes - Upgrade immediately");

        voting.addOption(newProposalId, "No - Keep current version");
        console.log("  Option 2 added: No - Keep current version");

        voting.addOption(newProposalId, "Abstain - Need more discussion");
        console.log("  Option 3 added: Abstain - Need more discussion");
        console.log("");

        // 7. 停止广播
        vm.stopBroadcast();

        // 8. 验证创建结果
        console.log("Step 4: Verifying proposal...");
        uint256 updatedProposalCount = voting.proposalCount();
        console.log("  Updated proposal count:", updatedProposalCount);
        console.log("  Verification:", updatedProposalCount == currentProposalCount + 1 ? "PASSED" : "FAILED");
        console.log("");

        // 9. 查询提案详情
        console.log("Step 5: Query proposal details...");
        (
            uint256 id,
            string memory retrievedTitle,
            uint256 groupId,
            uint256 optionCount,
            uint256 createdAt,
            uint256 deadline
        ) = voting.getProposal(newProposalId);

        console.log("====================================");
        console.log("Proposal Details");
        console.log("====================================");
        console.log("ID:", id);
        console.log("Title:", retrievedTitle);
        console.log("Group ID:", groupId);
        console.log("Option Count:", optionCount);
        console.log("Created At:", createdAt);
        console.log("Deadline:", deadline);
        console.log("");

        // 10. 查询各选项票数
        console.log("Voting Options:");
        for (uint256 i = 1; i <= optionCount; i++) {
            uint256 votes = voting.getVotes(newProposalId, i);
            console.log("  Option", i, "votes:", votes);
        }
        console.log("");

        // 11. 输出摘要
        console.log("====================================");
        console.log("Test Summary");
        console.log("====================================");
        console.log("Status: SUCCESS");
        console.log("Proposal ID:", newProposalId);
        console.log("Title:", title);
        console.log("Options Created:", optionCount);
        console.log("Voting Period: 7 days");
        console.log("");
        console.log("Next Steps:");
        console.log("1. Users can join the proposal using joinProposal()");
        console.log("2. Generate ZK proofs to vote anonymously");
        console.log("3. Query results after voting period");
        console.log("====================================");
    }
}
