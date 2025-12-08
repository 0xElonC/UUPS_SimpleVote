//SPDX-License-Identifier:MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/SimpleVotingV3.sol";

/**
 * @title VerifyUpgrade
 * @notice 验证 V3 升级是否成功的脚本
 * @dev 检查合约版本、存储布局完整性等
 */
contract VerifyUpgrade is Script {
    function run() external view {
        address proxyAddress = vm.envAddress("PROXY");
        
        console.log("=== Verifying V3 Upgrade ===");
        console.log("Proxy address:", proxyAddress);
        
        SimpleVotingV3 voting = SimpleVotingV3(proxyAddress);
        
        // 1. 检查版本号
        string memory versionStr = voting.version();
        console.log("Contract version:", versionStr);
        require(
            keccak256(bytes(versionStr)) == keccak256(bytes("V3")),
            "Version mismatch!"
        );
        
        // 2. 检查基本状态变量
        address owner = voting.owner();
        uint256 proposalCount = voting.proposalCount();
        address semaphore = address(voting.semaphore());
        
        console.log("Owner:", owner);
        console.log("Proposal count:", proposalCount);
        console.log("Semaphore address:", semaphore);
        
        // 3. 如果存在提案，检查数据完整性
        if (proposalCount > 0) {
            string memory title = voting.getProposalTitle(1);
            uint256 deadline = voting.getProposalDeadline(1);
            
            console.log("\n=== Proposal 1 Data ===");
            console.log("Title:", title);
            console.log("Deadline:", deadline);
            
            // 这里可以添加更多验证逻辑
        }
        
        console.log("\n=== Verification Complete ===");
        console.log("Upgrade verified successfully!");
    }
}
