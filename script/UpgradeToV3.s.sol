//SPDX-License-Identifier:MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/SimpleVotingV2.sol";
import "../src/SimpleVotingV3.sol";

/**
 * @title UpgradeToV3
 * @notice UUPS 升级脚本：从 SimpleVotingV2 升级到 SimpleVotingV3
 * @dev 使用方法:
 *   1. 设置环境变量 PROXY (V2代理合约地址)
 *   2. 设置环境变量 PRIVATE_KEY (管理员私钥)
 *   3. 运行: forge script script/UpgradeToV3.s.sol --rpc-url <RPC_URL> --broadcast
 */
contract UpgradeToV3 is Script {
    function run(address proxyAddress) external {
        // 从环境变量或默认配置读取私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log("=== Upgrading SimpleVoting from V2 to V3 ===");
        console.log("Proxy address:", proxyAddress);

        vm.startBroadcast(deployerPrivateKey);

        // 部署新的 V3 实现合约
        SimpleVotingV3 newImplV3 = new SimpleVotingV3();
        console.log("V3 implementation deployed at:", address(newImplV3));

        // 调用代理合约的 upgradeToAndCall 进行升级
        // 注意: 使用空 data，因为 V3 不需要额外的初始化参数
        SimpleVotingV2(proxyAddress).upgradeToAndCall(address(newImplV3), "");

        console.log("Upgrade completed successfully!");

        // 可选：调用 initializeV3 触发升级事件（如果需要）
        // SimpleVotingV3(proxyAddress).initializeV3();
        // console.log("initializeV3 called");

        vm.stopBroadcast();

        console.log("\n=== Upgrade Summary ===");
        console.log("Old version: V2");
        console.log("New version: V3");
        console.log("Proxy address:", proxyAddress);
        console.log("New implementation:", address(newImplV3));
    }
}
