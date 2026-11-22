// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SCRReportRegistry} from "../src/SCRReportRegistry.sol";

/// @notice Deploys SCRReportRegistry: deployer = admin + attester; the owner's wallet is also granted admin.
contract DeployRegistry is Script {
    address constant OWNER_ADMIN = 0x48808568033ae06edA42deF343102De46b2a343f;

    function run() external returns (SCRReportRegistry reg) {
        require(block.chainid == 137 || block.chainid == 80002, "unsupported chain");
        vm.startBroadcast();
        reg = new SCRReportRegistry(msg.sender, msg.sender);
        reg.grantRole(reg.DEFAULT_ADMIN_ROLE(), OWNER_ADMIN);
        vm.stopBroadcast();
        console2.log("chain", block.chainid);
        console2.log("SCRReportRegistry", address(reg));
    }
}
