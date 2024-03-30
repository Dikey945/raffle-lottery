// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /**
     * Events
     */
    event RaffleEnter(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link,) =
            helperConfig.activeNetworkConfig();
        // vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffllInitializesInOpenState() public view {
        assertEq(uint256(raffle.getRaffleState()), uint256(Raffle.RaffleState.OPEN));
    }

    function testRaffleRevertsWhenYouDontPay() public {
        //Arrange
        vm.prank(PLAYER);
        //Acct
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
        //Assert
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        //Arrange
        // vm.prank(PLAYER);

        console.log("Player balance: ", address(PLAYER).balance);
        //Act
        // So hoax() act like a combination of vm.prank() and vm.deal()
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        //Assert
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        hoax(PLAYER, entranceFee);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEnter(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterRaffleIsCalculating() public {
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleClosed.selector);
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRafflleNotOpen() public {
        // Arrange
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    // testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed
    // testCheckUpkeepRetrunsTrueWhenAllParametersAreGood
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.roll(block.number + 1);
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepRetrunsTrueWhenAllParametersAreGood() public {
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded,) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    //////////////////////////
    //// performUpkeep////////
    //////////////////////////

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();
        // Act
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
        );
        raffle.performUpkeep("");
    }

    modifier raffleEneteredAndTimePassed() {
        hoax(PLAYER, entranceFee);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEneteredAndTimePassed {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        console.log("requestId:");
        console.logBytes32(requestId);
        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        raffleEneteredAndTimePassed
        skipFork
    {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEneteredAndTimePassed skipFork {
        // Arrange
        uint256 additionalEntrance = 5;
        uint256 startingIndex = 1;
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrance; i++) {
            address player = address(uint160(i));
            hoax(player, entranceFee);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 prize = entranceFee * (additionalEntrance + 1);

        vm.recordLogs();
        raffle.performUpkeep(""); //emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 previousLastTimeStamp = raffle.getLastTimeStamp();

        // pretend to be chainlink vrf to get random number and pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));
        console.log("Winner Balance", raffle.getRecentWinner().balance);
        console.log("Prize", prize);
        // Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLengthOfPlayers() == 0);
        assert(raffle.getLastTimeStamp() > previousLastTimeStamp);
        assert(raffle.getRecentWinner().balance == prize);
    }
}
