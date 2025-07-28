//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {Game} from "../src/Game.sol";

contract DeployGame is Script {
    function deploy(
        uint256 _gracePeriod,
        uint256 _initialClaimFee,
        uint256 _feeIncreasePercentage,
        uint256 _platformFeePercentage
    ) public returns (Game) {
        vm.startBroadcast();
        Game game = new Game(_gracePeriod, _initialClaimFee, _feeIncreasePercentage, _platformFeePercentage);
        vm.stopBroadcast();
        return game;
    }

    function deployWithConfig() public returns (Game) {
        uint256 gracePeriod = 1 days;
        uint256 initialClaimFee = 0.01 ether;
        uint256 feeIncreasePercentage = 10; // 10%
        uint256 platformFeePercentage = 5; // 5%

        return deploy(gracePeriod, initialClaimFee, feeIncreasePercentage, platformFeePercentage);
    }
}
