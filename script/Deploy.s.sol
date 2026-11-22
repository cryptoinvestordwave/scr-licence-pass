// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SCRLicencePass} from "../src/SCRLicencePass.sol";

/// @notice Deploys SCRLicencePass.
///  - deployer (msg.sender) = admin + minter (runs the mint cron)
///  - OWNER_ADMIN (the owner's payout wallet) is ALSO granted admin, so the owner can always
///    revoke the deployer key from MetaMask if it is ever lost or compromised
///  - treasury = OWNER_ADMIN (USDC payments go straight there)
///  - USDC prices start at 0 = USDC sales disabled until the owner sets them
/// Usage: forge script script/Deploy.s.sol --rpc-url amoy|polygon --private-key $(cat KEY) --broadcast --verify
contract Deploy is Script {
    address constant OWNER_ADMIN = 0x48808568033ae06edA42deF343102De46b2a343f;
    address constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // native USDC
    address constant USDC_AMOY = 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582;    // Circle testnet USDC

    function run() external returns (SCRLicencePass pass) {
        address usdc;
        if (block.chainid == 137) usdc = USDC_POLYGON;
        else if (block.chainid == 80002) usdc = USDC_AMOY;
        else revert("unsupported chain");

        vm.startBroadcast();
        address deployer = msg.sender;
        pass = new SCRLicencePass(deployer, deployer, OWNER_ADMIN, IERC20(usdc));
        pass.grantRole(pass.DEFAULT_ADMIN_ROLE(), OWNER_ADMIN);
        vm.stopBroadcast();

        console2.log("chain", block.chainid);
        console2.log("SCRLicencePass", address(pass));
        console2.log("admin+minter", deployer);
        console2.log("admin+treasury", OWNER_ADMIN);
    }
}
