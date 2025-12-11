// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {SimpleVotingV6} from "../src/SimpleVotingV6.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title RedeployV6
 * @notice 重新部署 V6 合约 (替换损坏的代理)
 */
contract RedeployV6 is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address semaphoreAddress = 0xd4122b4ddf7B9832F73c728B1E9157409B071380; // Sepolia

        console.log("==========================================================");
        console.log("Redeploying SimpleVotingV6");
        console.log("==========================================================");
        console.log("Deployer:", deployer);
        console.log("Semaphore:", semaphoreAddress);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 V6 实现
        console.log("[1/3] Deploying SimpleVotingV6 implementation...");
        SimpleVotingV6 implementation = new SimpleVotingV6();
        console.log("Implementation deployed at:", address(implementation));
        console.log("");

        // 2. 准备初始化数据
        console.log("[2/3] Preparing initialization data...");
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV6.initialize.selector,
            semaphoreAddress
        );
        console.log("Init data prepared");
        console.log("");

        // 3. 部署代理
        console.log("[3/3] Deploying ERC1967Proxy...");
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        console.log("Proxy deployed at:", address(proxy));
        console.log("");

        vm.stopBroadcast();

        // 验证
        SimpleVotingV6 voting = SimpleVotingV6(address(proxy));
        console.log("==========================================================");
        console.log("Deployment Verification");
        console.log("==========================================================");
        console.log("Version:", voting.version());
        console.log("Owner:", voting.owner());
        console.log("Semaphore:", address(voting.semaphore()));
        console.log("Proposal Count:", voting.proposalCount());
        console.log("");

        console.log("==========================================================");
        console.log("Deployment successful!");
        console.log("==========================================================");
        console.log("");
        console.log("Next steps:");
        console.log("1. Update PROXY in .env to:", address(proxy));
        console.log("2. Create proposals using CreateLXDAOProposal.s.sol");
        console.log("3. Test voting flow");
    }
}
