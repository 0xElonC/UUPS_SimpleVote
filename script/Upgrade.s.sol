//SPDX-License-Identifier:MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/SimpleVoting.sol";


contract Upgrade is Script{
    function run() external {
        address proxyAddress = vm.envAddress("PROXY");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        console.log(proxyAddress);
        vm.startBroadcast(deployerPrivateKey);

        SimpleVoting newImpl = new SimpleVoting();

        //升级
        SimpleVoting(proxyAddress).upgradeToAndCall(address(newImpl),"");

        console.log("New implementation deployed:", address(newImpl));
        vm.stopBroadcast();
    }
}