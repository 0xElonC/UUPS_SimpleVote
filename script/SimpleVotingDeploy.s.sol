// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { SimpleVoting } from "../src/SimpleVoting.sol";
contract SimpleVotingDeploy is Script{
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        //部署实现合约
        SimpleVoting simpelVoting = new SimpleVoting();

        //初始化calldata
        bytes memory initData = abi.encodeWithSelector(simpelVoting.initialize.selector,vm.addr(vm.envUint("PRIVATE_KEY")));

        ERC1967Proxy proxy = new ERC1967Proxy(address(simpelVoting), initData);
        console.log("Implementation:", address(simpelVoting));
        console.log("Proxy:", address(proxy));
        vm.stopBroadcast();
    }
}