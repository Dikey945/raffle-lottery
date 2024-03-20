// Layout of Contract:
// License
// Pragma version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

//Layout of Functions:
// Constructor
// receive function (if exists)
// fallback function (if exists)
// external functions
// public functions
// internal functions
// private functions
// view and pure functions

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Raffle
 * @author Dikey945
 * @notice This contract is for creating a sample raffle
 * @dev Implemnents Chainlink VRFv2
 */

contract Raffle is VRFConsumerBaseV2 {
    /** Errors */
    error Raffle__NotEnoughEthSent();
    error Raffle__NotEnoughPlayers();
    error Raffle__TranscactionReverted();
    error Raffle__RaffleClosed();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 players,
        uint256 state
    );

    /** Type declarations */
    enum RaffleState {
        OPEN,
        CLOSED
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable i_entranceFee;
    /**  @dev duration of the lottery in seconds */
    uint256 private immutable i_interval;
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable private s_recentWinner;
    RaffleState private s_raffleState;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);

    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = _gasLane;
        i_subscriptionId = _subscriptionId;
        i_callbackGasLimit = _callbackGasLimit;
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState == RaffleState.CLOSED) {
            revert Raffle__RaffleClosed();
        }
        s_players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    // When is the winner supposed to be picked?
    /**
     * @dev this is the function that the Chainlink Automation node call
     * to see if it's time to perform the upkeep:
     * 1. the time interval has passed between ruffle runs
     * 2. The raffle is in open state
     * 3. The contracts have players
     * 4. The subscription is funded with link
     */
    function checkUpkeep(
        bytes memory /**checkData*/
    ) public view returns (bool upkeepNeeded, bytes memory) {
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    // To pikc a winner, we need to do next:
    // 1. Get a random number
    // 2. Pick a winner based on the random number
    // 3. Be automatically called
    function performUpkeep(bytes calldata /**performData*/) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CLOSED;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // id of subscription funded with link
            REQUEST_CONFIRMATIONS, // number of confirmations that our number to be condsidered valid
            i_callbackGasLimit, // to not overspend on call call back function
            NUM_WORDS // number of random numbers
        );
    }

    function fulfillRandomWords(
        uint256 /**requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // Checks

        // Effects (all actions that change the state of the contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;
        // reset the players array
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);

        // Interactions (other contracts and external transactions)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TranscactionReverted();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getInterval() external view returns (uint256) {
        return i_interval;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
