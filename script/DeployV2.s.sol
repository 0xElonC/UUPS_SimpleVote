// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVotingV2} from "../src/SimpleVotingV2.sol";
import {Semaphore} from "semaphore/packages/contracts/contracts/Semaphore.sol";
import {ISemaphoreVerifier} from "semaphore/packages/contracts/contracts/interfaces/ISemaphoreVerifier.sol";
import {SemaphoreVerifier} from "semaphore/packages/contracts/contracts/base/SemaphoreVerifier.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployV2
 * @author Sue
 * @notice 部署脚本 - SimpleVotingV2 (基于 Semaphore 的匿名投票系统)
 *
 * @dev 部署流程:
 * 1. 部署 Semaphore 验证器
 * 2. 部署 SimpleVotingV2 实现合约
 * 3. 部署 UUPS 代理合约
 * 4. 初始化代理
 * 5. 验证部署
 *
 * 使用方法:
 * forge script script/DeployV2.s.sol \
 *   --rpc-url $RPC_URL \
 *   --broadcast \
 *   --verify \
 *   -vvvv
 */
contract DeployV2 is Script {
    /// @notice SemaphoreVerifier 合约地址
    SemaphoreVerifier public verifier;

    /// @notice Semaphore 合约地址
    Semaphore public semaphore;

    /// @notice SimpleVotingV2 实现合约地址
    SimpleVotingV2 public implementation;

    /// @notice UUPS 代理合约地址
    ERC1967Proxy public proxy;

    /// @notice SimpleVotingV2 实例 (通过代理访问)
    SimpleVotingV2 public voting;

    /**
     * @notice 部署主函数
     */
    function run() external {
        // 1. 获取部署者私钥和地址
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("====================================");
        console.log("Deploying SimpleVotingV2 with Semaphore");
        console.log("====================================");
        console.log("Deploying with account:", deployer);
        console.log("Account balance:", deployer.balance);
        console.log("");

        // 2. 开始广播交易
        vm.startBroadcast(deployerPrivateKey);

        // 3. 部署 SemaphoreVerifier
        console.log("Step 1: Deploying SemaphoreVerifier...");
        verifier = new SemaphoreVerifier();
        console.log("  SemaphoreVerifier deployed at:", address(verifier));
        console.log("");

        // 4. 部署 Semaphore
        console.log("Step 2: Deploying Semaphore...");
        semaphore = new Semaphore(ISemaphoreVerifier(address(verifier)));
        console.log("  Semaphore deployed at:", address(semaphore));
        console.log("");

        // 5. 部署 SimpleVotingV2 实现
        console.log("Step 3: Deploying SimpleVotingV2 implementation...");
        implementation = new SimpleVotingV2();
        console.log("  Implementation deployed at:", address(implementation));
        console.log("");

        // 6. 准备初始化数据
        console.log("Step 4: Preparing initialization data...");
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV2.initialize.selector,
            address(semaphore),
            deployer
        );
        console.log("  Semaphore address:", address(semaphore));
        console.log("  Admin address:", deployer);
        console.log("");

        // 7. 部署 UUPS 代理
        console.log("Step 5: Deploying UUPS proxy...");
        proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("  Proxy deployed at:", address(proxy));
        console.log("");

        // 7. 停止广播
        vm.stopBroadcast();

        // 8. 验证部署
        console.log("Step 6: Verifying deployment...");
        voting = SimpleVotingV2(address(proxy));

        console.log("====================================");
        console.log("Deployment Verification");
        console.log("====================================");
        console.log("Owner:", voting.owner());
        console.log("Semaphore:", address(voting.semaphore()));
        console.log("Proposal count:", voting.proposalCount());
        console.log("");

        // 9. 输出摘要
        console.log("====================================");
        console.log("Deployment Summary");
        console.log("====================================");
        console.log("Verifier address:      ", address(verifier));
        console.log("Semaphore address:     ", address(semaphore));
        console.log("Implementation address:", address(implementation));
        console.log("Proxy address:         ", address(proxy));
        console.log("");
        console.log("Use the Proxy address for all interactions:");
        console.log(address(proxy));
        console.log("====================================");
    }
}
