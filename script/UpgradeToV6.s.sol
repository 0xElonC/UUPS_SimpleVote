// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVotingV6} from "../src/SimpleVotingV6.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title UpgradeToV6
 * @notice 将 SimpleVoting 从 V5 升级到 V6
 * @dev V6 核心变化:
 *      - 移除 SemaphoreGroups 继承
 *      - 完全使用外部 Semaphore 合约
 *      - 所有 group 操作通过 semaphore.xxx()
 *
 * 使用方式:
 * forge script script/UpgradeToV6.s.sol --rpc-url $RPC_URL --broadcast --legacy
 */
contract UpgradeToV6 is Script {
    function run() external {
        // 从环境变量读取配置
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY");

        address deployer = vm.addr(deployerPrivateKey);

        console.log("==========================================================");
        console.log("Upgrading SimpleVoting to V6");
        console.log("==========================================================");
        console.log("Deployer:", deployer);
        console.log("Proxy Address:", proxyAddress);

        // 获取代理合约当前状态
        SimpleVotingV6 proxy = SimpleVotingV6(proxyAddress);

        console.log("Current Owner:", proxy.owner());
        console.log("Current Version:", proxy.version());
        console.log("");

        // 开始广播交易
        vm.startBroadcast(deployerPrivateKey);

        // [1/5] 部署新的 V6 实现合约
        console.log("[1/5] Deploying SimpleVotingV6 implementation...");
        SimpleVotingV6 implementationV6 = new SimpleVotingV6();
        console.log("V6 Implementation deployed at:", address(implementationV6));
        console.log("");

        // [2/5] 准备升级数据
        console.log("[2/5] Preparing upgrade data...");
        // V6 初始化数据: initializeV6(address(0)) 保持当前 Semaphore 实例
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV6.initializeV6.selector,
            address(0)  // 保持当前 Semaphore,不切换
        );
        console.log("Init data prepared (keeping current Semaphore instance)");
        console.log("");

        // [3/5] 执行升级
        console.log("[3/5] Upgrading proxy to V6...");
        UUPSUpgradeable(proxyAddress).upgradeToAndCall(
            address(implementationV6),
            initData
        );
        console.log("Proxy upgraded successfully!");
        console.log("");

        // [4/5] 验证升级
        console.log("[4/5] Verifying upgrade...");
        string memory newVersion = proxy.version();
        console.log("New Version:", newVersion);
        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("V6")),
            "Version mismatch"
        );
        console.log("");

        // [5/5] 验证数据完整性
        console.log("[5/5] Verifying data integrity...");
        uint256 proposalCount = proxy.proposalCount();
        console.log("Proposal Count:", proposalCount);

        if (proposalCount > 0) {
            console.log("");
            console.log("Proposal 1 Info:");
            (
                uint256 id,
                string memory title,
                uint256 groupId,
                uint256 optionCount,
                uint256 createdAt,
                bool isActive
            ) = proxy.getProposalInfo(1);

            console.log("  ID:", id);
            console.log("  Title:", title);
            console.log("  Group ID:", groupId);
            console.log("  Option Count:", optionCount);
            console.log("  Created At:", createdAt);
            console.log("  Is Active:", isActive);

            console.log("");
            console.log("IMPORTANT: V5 proposals' groups are NOT in external Semaphore!");
            console.log("Recommendation: Call markOldProposalsInvalid() to disable old proposals");
        }

        vm.stopBroadcast();

        console.log("");
        console.log("==========================================================");
        console.log("Upgrade to V6 completed successfully!");
        console.log("==========================================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Call markOldProposalsInvalid() to disable V5 proposals");
        console.log("2. Create new proposals using V6 (they will use external Semaphore)");
        console.log("3. Users can join new proposals and vote successfully");
        console.log("");
        console.log("Command to disable old proposals:");
        console.log("cast send", proxyAddress, '"markOldProposalsInvalid()"', "--rpc-url $RPC_URL --private-key $PRIVATE_KEY");
    }
}
