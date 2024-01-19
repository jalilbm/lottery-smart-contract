// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {console} from "forge-std/Test.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address vrfCoordinatorAddress,
        uint256 deployerKey
    ) public returns (uint64) {
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinatorAddress)
            .createSubscription();
        vm.stopBroadcast();
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 subscriptionFundAmount = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, subId, link, deployerKey);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                subscriptionFundAmount
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                subscriptionFundAmount,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address consumer) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(vrfCoordinator, subId, consumer, deployerKey);
    }

    function addConsumer(
        address vrfCoordinator,
        uint64 subId,
        address consumer,
        uint256 deployerKey
    ) public {
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, consumer);
        vm.stopBroadcast();
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );

        addConsumerUsingConfig(raffle);
    }
}
