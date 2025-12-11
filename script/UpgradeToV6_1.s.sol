// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "../src/SimpleVotingV6.sol";

/**
 * @title UpgradeToV6_1
 * @notice 从 V6 升级到 V6.1 (隐私优化版本)
 * @dev 升级内容:
 *      - VoteCast 事件移除 optionId 参数
 *      - 防止时间关联攻击
 *      - 存储布局完全兼容,无需 reinitializer
 *
 * @dev 使用方法:
 *      forge script script/UpgradeToV6_1.s.sol --rpc-url $SEPOLIA_RPC --broadcast
 */
contract UpgradeToV6_1 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address proxyAddress = vm.envAddress("PROXY_ADDRESS");

        require(proxyAddress != address(0), "PROXY_ADDRESS not set in .env");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 获取当前 Proxy 合约
        console.log("=== Current Proxy Information ===");
        SimpleVotingV6 proxy = SimpleVotingV6(proxyAddress);

        string memory currentVersion = proxy.version();
        console.log("Current version:", currentVersion);

        address currentOwner = proxy.owner();
        console.log("Current owner:", currentOwner);

        uint256 currentProposalCount = proxy.proposalCount();
        console.log("Current proposalCount:", currentProposalCount);

        // 2. 部署新的 V6.1 实现合约
        console.log("\n=== Deploying V6.1 Implementation ===");
        SimpleVotingV6 newImplementation = new SimpleVotingV6();
        console.log("New implementation deployed at:", address(newImplementation));

        // 3. 执行升级 (UUPS 模式 - 使用 upgradeToAndCall)
        console.log("\n=== Upgrading Proxy to V6.1 ===");
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("Upgrade transaction executed");

        // 4. 验证升级结果
        console.log("\n=== Verifying Upgrade ===");

        string memory newVersion = proxy.version();
        console.log("New version:", newVersion);

        address newOwner = proxy.owner();
        console.log("Owner after upgrade:", newOwner);

        uint256 newProposalCount = proxy.proposalCount();
        console.log("ProposalCount after upgrade:", newProposalCount);

        // 5. 断言验证
        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("V6.1")),
            "Version upgrade failed"
        );
        require(newOwner == currentOwner, "Owner should remain unchanged");
        require(newProposalCount == currentProposalCount, "ProposalCount should remain unchanged");

        console.log("\n=== Upgrade Successful ===");
        console.log("Proxy Address:", proxyAddress);
        console.log("New Implementation:", address(newImplementation));
        console.log("Version: V6 -> V6.1");
        console.log("\nV6.1 Privacy Improvements:");
        console.log("- VoteCast event no longer exposes optionId");
        console.log("- Protection against timing correlation attacks");
        console.log("- Frontend should listen to VoteCast(proposalId) and refresh vote counts");

        vm.stopBroadcast();
    }
}
