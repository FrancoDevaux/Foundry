// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {FundMe} from "../src/FundMe.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployFundMe is Script {
    function run() external returns (FundMe) {
        // Beofore startBroadcast, the contract is not deployed, "not a real tx"
        HelperConfig helperConfig = new HelperConfig(); // create a new contract
        address ethUsdPriceFeed = helperConfig.activeNetworkConfig(); // call a function

        // After stopBroadcast, the contract is deployed, "real tx"
        vm.startBroadcast();
        FundMe fundMe = new FundMe(ethUsdPriceFeed);
        vm.stopBroadcast();
        return fundMe;
    }
}
