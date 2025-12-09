// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVotingV4} from "../src/SimpleVotingV4.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title UpgradeToV4
 * @author Sue
 * @notice V3 → V4 升级脚本
 *
 * 升级步骤:
 * 1. 部署新的 V4 实现合约
 * 2. 通过代理合约调用 upgradeToAndCall()
 * 3. 执行 initializeV4() 迁移数据
 */
contract UpgradeToV4 is Script {
    // ========== 配置 ==========

    // 从环境变量读取代理地址（尝试多个可能的变量名）
    address proxy;

    // ========== 主函数 ==========

    function run() external {
        // 1. 获取部署者私钥和代理地址
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // 尝试读取代理地址（兼容多种环境变量名）
        try vm.envAddress("PROXY_ADDRESS") returns (address addr) {
            proxy = addr;
        } catch {
            proxy = vm.envAddress("PROXY");
        }

        console.log("==========================================================");
        console.log("Upgrading SimpleVoting to V4");
        console.log("==========================================================");
        console.log("Proxy Address:", proxy);
        console.log("Deployer:", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        // 2. 部署新的 V4 实现合约
        console.log("\n[Step 1] Deploying V4 Implementation...");
        SimpleVotingV4 implementationV4 = new SimpleVotingV4();
        console.log("V4 Implementation deployed at:", address(implementationV4));

        // 3. 验证当前版本
        SimpleVotingV4 proxyContract = SimpleVotingV4(proxy);
        string memory currentVersion = proxyContract.version();
        console.log("\n[Step 2] Current Version:", currentVersion);

        // 4. 升级到 V4（并调用 initializeV4）
        console.log("\n[Step 3] Upgrading to V4...");
        bytes memory initData = abi.encodeCall(SimpleVotingV4.initializeV4, ());

        proxyContract.upgradeToAndCall(address(implementationV4), initData);

        // 5. 验证升级成功
        console.log("\n[Step 4] Verifying Upgrade...");
        string memory newVersion = proxyContract.version();
        console.log("New Version:", newVersion);

        require(
            keccak256(bytes(newVersion)) == keccak256(bytes("V4")),
            "Upgrade failed: version mismatch"
        );

        // 6. 显示提案状态（如果有提案）
        uint256 proposalCount = proxyContract.proposalCount();
        console.log("\n[Step 5] Proposal Migration Status:");
        console.log("Total Proposals:", proposalCount);

        if (proposalCount > 0) {
            for (uint256 i = 1; i <= proposalCount && i <= 5; i++) {
                (
                    uint256 id,
                    string memory title,
                    ,
                    ,
                    uint256 createdAt,
                    bool isActive
                ) = proxyContract.getProposalInfo(i);

                console.log("\nProposal", id);
                console.log("  Title:", title);
                console.log("  Created:", createdAt);
                console.log("  Active:", isActive);
            }

            if (proposalCount > 5) {
                console.log("\n... (showing first 5 proposals only)");
            }
        }

        vm.stopBroadcast();

        console.log("\n==========================================================");
        console.log("Upgrade to V4 completed successfully!");
        console.log("==========================================================");
    }
}
