// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

import "forge-std/Script.sol";
import "../src/SimpleVotingV6.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployCleanV6
 * @notice 全新部署干净版 V6（无 v5UpgradeThreshold 历史包袱）
 * @dev 使用场景：开发阶段的代码优化和重新部署
 */
contract DeployCleanV6 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address semaphoreAddress = vm.envAddress("SEMAPHORE_ADDRESS");

        require(semaphoreAddress != address(0), "SEMAPHORE_ADDRESS not set in .env");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 V6 实现合约
        console.log("=== Deploying SimpleVotingV6 Implementation ===");
        SimpleVotingV6 implementation = new SimpleVotingV6();
        console.log("Implementation deployed at:", address(implementation));

        // 2. 准备初始化数据（调用 initialize - 全新部署用）
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV6.initialize.selector,
            semaphoreAddress
        );

        // 3. 部署 ERC1967Proxy
        console.log("\n=== Deploying ERC1967Proxy ===");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));

        // 4. 验证初始化结果
        console.log("\n=== Verifying Initialization ===");
        SimpleVotingV6 voting = SimpleVotingV6(address(proxy));

        string memory version = voting.version();
        console.log("Version:", version);

        address semaphoreAddr = address(voting.semaphore());
        console.log("Semaphore address:", semaphoreAddr);

        uint256 count = voting.proposalCount();
        console.log("Initial proposalCount:", count);

        // 5. 验证结果正确性
        require(
            keccak256(bytes(version)) == keccak256(bytes("V6")),
            "Version mismatch"
        );
        require(semaphoreAddr == semaphoreAddress, "Semaphore address mismatch");
        require(count == 0, "ProposalCount should be 0");

        console.log("\n=== Deployment Successful ===");
        console.log("New Proxy Address:", address(proxy));
        console.log("Implementation Address:", address(implementation));

        vm.stopBroadcast();
    }
}
