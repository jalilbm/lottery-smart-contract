// SPDX-License-Identifier: MIT

pragma solidity ^0.8.21;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle private raffle;
    HelperConfig private helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerKey;

    address private constant PLAYER = address(1);
    uint256 private constant STARTING_BALANCE = 10 ether;
    uint256 private constant INVALID_ETH_AMOUNT = 0.001 ether;
    uint256 private constant VALID_ETH_AMOUNT = 0.01 ether;

    /** Events */

    event EnteredRaffle(address indexed player);
    event RequestedRaffleWinner(uint256 requiestId);
    event PickedWinner(address indexed winner);

    /** Modifiers */

    modifier raffleEntered() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    /** Functions */

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        console.log("address(raffle).balance", address(raffle).balance);
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();

        deal(PLAYER, STARTING_BALANCE);
    }

    function testRaffleIntializesInOpenState() external view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    ///////////////////////////
    // enterRaffle          //
    /////////////////////////

    function testRaffleRevertsWhenYouDontPayEnoughEth() external {
        // Arrange
        vm.startPrank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle{value: INVALID_ETH_AMOUNT}();
        vm.stopPrank();
    }

    function testRaffleRecordsPlayerWHenTheEnter() external {
        // Arrange
        vm.startPrank(PLAYER);
        // Act
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.stopPrank();
        // Assert
        assert(raffle.getPlayers()[0] == PLAYER);
    }

    function testEmitsEventOnEnterance() external {
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(address(PLAYER));
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.stopPrank();
    }

    function testCantEnterWhenRaffleIsCalculating() external {
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.startPrank(PLAYER);
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.stopPrank();
    }

    ///////////////////////////
    // checkUpkeep          //
    /////////////////////////

    function testCheckUpkeepReturnsFalseIfHasNoBalance() external {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen()
        external
        raffleEntered
    {
        // Arange
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arange
        vm.startPrank(PLAYER);
        raffle.enterRaffle{value: VALID_ETH_AMOUNT}();
        vm.stopPrank();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood()
        public
        raffleEntered
    {
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    ///////////////////////////
    // performUpkeep        //
    /////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        external
        raffleEntered
    {
        // Act
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public skipFork {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        console.log("currentBalance", currentBalance);
        // console.log("rState", rState);

        // Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        external
        raffleEntered
    {
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Raffle.RaffleState raffleState = raffle.getRaffleState();

        // Assert
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    ///////////////////////////
    // fulfillRandomWords   //
    /////////////////////////

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) external skipFork raffleEntered {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        external
        skipFork
        raffleEntered
    {
        // Arrange
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        vm.expectEmit(true, false, false, false, address(raffle));
        emit PickedWinner(PLAYER);
        uint256 initialPlayerBalance = PLAYER.balance;
        uint256 initialRaffleBalance = address(raffle).balance;

        // Act
        vm.startBroadcast();
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        vm.stopBroadcast();

        // Assert
        address recentWinner = raffle.getRecentWinner();
        assert(recentWinner == PLAYER);
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getPlayers().length == 0);
        assert(raffle.getLastTimeStamp() == block.timestamp);
        assert(address(raffle).balance == 0);
        assert(PLAYER.balance == initialPlayerBalance + initialRaffleBalance);
    }
}
