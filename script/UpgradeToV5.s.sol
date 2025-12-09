// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/SimpleVotingV5.sol";

/**
 * @title UpgradeToV5 部署脚本
 * @author Sue
 * @notice 将 SimpleVoting 代理合约从 V4 升级到 V5
 *
 * @dev 升级步骤:
 * 1. 部署新的 SimpleVotingV5 实现合约
 * 2. 通过代理调用 upgradeToAndCall 升级到 V5
 * 3. 调用 initializeV5() 触发升级事件
 * 4. 验证升级成功
 *
 * @dev V5 升级内容:
 * - joinProposal 函数改为直接操作 Merkle Tree（运行时行为改变）
 * - 用户可以自由加入任何激活的提案
 * - 不需要数据迁移（所有 V4 数据保持不变）
 */
contract UpgradeToV5 is Script {
    function run() external {
        // 从环境变量读取配置
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("Upgrading SimpleVoting to V5");
        console.log("==========================================================");
        console.log("Deployer:", deployer);
        console.log("Proxy Address:", proxyAddress);

        // 连接到现有代理合约
        SimpleVotingV5 proxy = SimpleVotingV5(proxyAddress);

        // 验证部署者是合约所有者
        address currentOwner = proxy.owner();
        console.log("Current Owner:", currentOwner);
        require(deployer == currentOwner, "Deployer is not the owner");

        // 获取当前版本
        string memory currentVersion = proxy.version();
        console.log("Current Version:", currentVersion);

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署新的 V5 实现合约
        console.log("\n[1/4] Deploying SimpleVotingV5 implementation...");
        SimpleVotingV5 implementationV5 = new SimpleVotingV5();
        console.log("V5 Implementation deployed at:", address(implementationV5));

        // 2. 准备初始化调用数据
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV5.initializeV5.selector
        );

        // 3. 升级代理到 V5
        console.log("\n[2/4] Upgrading proxy to V5...");
        proxy.upgradeToAndCall(address(implementationV5), initData);
        console.log("Proxy upgraded successfully!");

        vm.stopBroadcast();

        // 4. 验证升级
        console.log("\n[3/4] Verifying upgrade...");
        string memory newVersion = proxy.version();
        console.log("New Version:", newVersion);
        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("V5")),
            "Version verification failed"
        );

        // 5. 验证数据完整性
        console.log("\n[4/4] Verifying data integrity...");
        uint256 proposalCount = proxy.proposalCount();
        console.log("Proposal Count:", proposalCount);

        if (proposalCount > 0) {
            // 检查提案 1 的信息
            (
                uint256 id,
                string memory title,
                uint256 groupId,
                uint256 optionCount,
                uint256 createdAt,
                bool isActive
            ) = proxy.getProposalInfo(1);

            console.log("\nProposal 1 Info:");
            console.log("  ID:", id);
            console.log("  Title:", title);
            console.log("  Group ID:", groupId);
            console.log("  Option Count:", optionCount);
            console.log("  Created At:", createdAt);
            console.log("  Is Active:", isActive);

            // 检查 Group 大小
            uint256 groupSize = proxy.getMerkleTreeSize(groupId);
            console.log("  Group Size:", groupSize);
        }

        console.log("\n==========================================================");
        console.log("Upgrade to V5 completed successfully!");
        console.log("==========================================================");
        console.log("\nV5 Features:");
        console.log("- Users can freely join any active proposal");
        console.log("- No admin approval required");
        console.log("- Direct Merkle Tree manipulation (bypasses permission checks)");
        console.log("- All V4 data preserved");
        console.log("\nNext Steps:");
        console.log("1. Test user joining: forge script script/TestV5JoinProposal.s.sol");
        console.log("2. Verify on block explorer (if on testnet/mainnet)");
        console.log("==========================================================");
    }
}
