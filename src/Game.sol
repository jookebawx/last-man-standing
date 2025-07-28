    //SPDX-License Identifier: MIT

pragma solidity ^0.8.20;

contract Game {
    /*Type Declarations*/
    enum gameState {
        OPEN,
        CALCULATING,
        CLOSED
    }

    /*State Variables*/
    uint256 private s_gracePeriod;
    uint256 private s_initialClaimFee;
    uint256 private s_feeIncreasePercentage; // Percentage increase for claim fee after each round
    // Example: if feeIncreasePercentage is 10, the claim fee increases by 10% after each round
    // If initialClaimFee is 100, after one round it will be 110, after two rounds it will be 121, and so on.
    // This allows for dynamic adjustment of claim fees based on the number of rounds played.
    uint256 private s_claimFee; // Current claim fee, initialized to initialClaimFee
    uint256 private s_platformFeePercentage;
    uint256 private s_feeIncreaseCounter;
    uint256 private constant PAYOUTPERCENTAGE = 10;
    address payable[] private s_participants;
    address private s_currentKing;
    address private s_previousKing;
    uint256 private s_lastClaimFee;
    uint256 private s_pot;
    uint256 private s_platformProfit;
    uint256 private s_lastTimestamp;
    address private immutable OWNER = msg.sender;
    gameState private s_currentGameState;

    /*Error*/
    error Game__InsufficientClaimFee();
    error Game__GameNotOpen();
    error Game__UnauthorizedAccess();
    error Game__CannotClaimThrone();
    error Game__FundTransferFailed();
    error Game__NoPotToWithdraw();
    error Game__GameisOpen();
    error Game__NoWinner();
    /*Events*/

    event ThroneClaimed(address indexed participant);
    event WinnerDeclared(address indexed winner);

    constructor(
        uint256 _gracePeriod,
        uint256 _initialClaimFee,
        uint256 _feeIncreasePercentage,
        uint256 _platformFeePercentage
    ) {
        s_gracePeriod = _gracePeriod;
        s_initialClaimFee = _initialClaimFee;
        s_feeIncreasePercentage = _feeIncreasePercentage;
        s_platformFeePercentage = _platformFeePercentage;
        s_claimFee = s_initialClaimFee;
        s_currentGameState = gameState.OPEN;
        s_pot = 0;
        s_platformProfit = 0;
        s_lastClaimFee = 0;
        s_currentKing = address(0);
        s_feeIncreaseCounter = 0;
        s_lastTimestamp = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                                OWNER FUNCTION
        //////////////////////////////////////////////////////////////*/
    modifier onlyOwner() {
        if (msg.sender != OWNER) {
            revert Game__UnauthorizedAccess();
        }
        _;
    }

    function UpdateGracePeriod(uint256 _gracePeriod) external onlyOwner {
        s_gracePeriod = _gracePeriod;
    }

    function UpdateInitialClaimFee(uint256 _initialClaimFee) external onlyOwner {
        s_initialClaimFee = _initialClaimFee;
        uint256 currentClaimFee = _initialClaimFee;
        for (uint256 i = 0; i < s_feeIncreaseCounter; i++) {
            currentClaimFee = currentClaimFee * (100 + s_feeIncreasePercentage) / 100; // Reset claim fee to initial value
        }
        if (s_claimFee < currentClaimFee) {
            s_claimFee = currentClaimFee; // Update claim fee to the new initial value if it's lower
        }
    }

    function UpdateFeeIncreasePercentage(uint256 _feeIncreasePercentage) external onlyOwner {
        s_feeIncreasePercentage = _feeIncreasePercentage;
    }

    function withdrawPlatformFees() external onlyOwner {
        require(s_platformProfit > 0, Game__NoPotToWithdraw());
        uint256 amountToWithdraw = s_platformProfit;
        s_platformProfit = 0; // Reset the platform profit after withdrawal
        (bool success,) = msg.sender.call{value: amountToWithdraw}("");
        require(success, Game__FundTransferFailed());
    }

    function getPlatformProfit() external view onlyOwner returns (uint256) {
        return s_platformProfit;
    }

    function resetGame() external onlyOwner {
        require(s_currentGameState == gameState.CLOSED, Game__GameisOpen());
        uint256 currentPot = s_pot;
        address currentKing = s_currentKing;
        s_pot = 0;
        if (currentPot > 0) {
            (bool success,) = payable(currentKing).call{value: currentPot}("");
            require(success, Game__FundTransferFailed());
        }
        s_lastTimestamp = block.timestamp; // Reset the last timestamp to current time
        s_currentGameState = gameState.OPEN; // Reset the game state to OPEN
        s_currentKing = address(0); // Reset the current king
        s_previousKing = address(0); // Reset the previous king
            // Reset the pot
        s_participants = new address payable[](0); // Clear participants list
        s_feeIncreaseCounter = 0; // Reset fee increase counter
        s_claimFee = s_initialClaimFee; // Reset claim fee to initial value
    }
    /*//////////////////////////////////////////////////////////////
                                KING FUNCTION
        //////////////////////////////////////////////////////////////*/

    function withdrawWinning() public payable {
        require(msg.sender == s_currentKing, Game__UnauthorizedAccess());
        require(s_currentGameState == gameState.CALCULATING, Game__GameNotOpen());
        require(s_pot > 0, Game__NoPotToWithdraw());
        uint256 amountToWithdraw = s_pot;
        s_pot = 0; // Reset the pot after withdrawal
        (bool success,) = msg.sender.call{value: amountToWithdraw}("");
        require(success, Game__FundTransferFailed());
        s_currentGameState = gameState.CLOSED; // Close the game after withdrawal
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIMANT FUNCTION
        //////////////////////////////////////////////////////////////*/
    function claimThrone() public payable {
        // Check if the game is still within the grace period
        if (s_lastTimestamp + s_gracePeriod > block.timestamp) {
            _ThroneClaim();
        } else {
            // Grace period over, move to CALCULATING state and declare winner
            s_currentGameState = gameState.CALCULATING;
            declareWinner();
            revert Game__GameNotOpen();
        }
    }

    function _ThroneClaim() internal {
        require(msg.value >= s_claimFee, Game__InsufficientClaimFee());
        require(s_currentGameState == gameState.OPEN, Game__GameNotOpen());
        require(s_currentKing != msg.sender, Game__CannotClaimThrone());

        s_lastClaimFee = msg.value; // Store the last claim fee before updating
        s_previousKing = s_currentKing; // Store the previous king before updating
        s_participants.push(payable(msg.sender));

        uint256 newClaimFee = (msg.value * (100 + s_feeIncreasePercentage)) / 100;
        s_claimFee = newClaimFee; // Increase claim fee by the specified percentage

        s_participants.push(payable(msg.sender));
        if (s_currentKing != address(0)) {
            uint256 kingPayout = (msg.value * PAYOUTPERCENTAGE) / 100;
            s_pot += msg.value * (100 - s_platformFeePercentage - PAYOUTPERCENTAGE) / 100;
            address currentKing = s_currentKing;
            s_currentKing = msg.sender;
            // If there is a current king, transfer the payout fee to them
            (bool success,) = payable(currentKing).call{value: kingPayout}("");
            require(success, Game__FundTransferFailed());
        } else {
            // If there is no current king, add the full amount to the pot
            s_pot += msg.value * (100 - s_platformFeePercentage) / 100;
            s_currentKing = msg.sender; // Set the new king
        }
        // Deduct platform fee from the pot
        s_platformProfit += (msg.value * s_platformFeePercentage) / 100;
        s_feeIncreaseCounter += 1; // Increment the fee increase counter
        emit ThroneClaimed(msg.sender);
    }

    function declareWinner() public {
        require(block.timestamp > s_lastTimestamp + s_gracePeriod, Game__GameisOpen());
        require(s_currentKing != address(0), Game__NoWinner());
        require(s_participants.length > 0, Game__NoWinner());
        s_currentGameState = gameState.CALCULATING; // Set the game state to CALCULATING
        address currentKing = s_currentKing; // Store the current king
        emit WinnerDeclared(currentKing);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTER FUNCTION
        //////////////////////////////////////////////////////////////*/
    function getGracePeriod() external view returns (uint256) {
        return s_gracePeriod;
    }

    function getPot() external view returns (uint256) {
        return s_pot;
    }

    function getOwner() external view returns (address) {
        return OWNER;
    }

    function getCurrentClaimFee() external view returns (uint256) {
        return s_claimFee;
    }

    function getInitialClaimFee() external view returns (uint256) {
        return s_initialClaimFee;
    }

    function getLastClaimFee() external view returns (uint256) {
        return s_lastClaimFee;
    }

    function getCurrentKing() external view returns (address) {
        return s_currentKing;
    }

    function getPreviousKing() external view returns (address) {
        return s_previousKing;
    }

    function getFeeIncreasePercentage() external view returns (uint256) {
        return s_feeIncreasePercentage;
    }

    function getPlatformFeePercentage() external view returns (uint256) {
        return s_platformFeePercentage;
    }

    function getCurrentGameState() external view returns (gameState) {
        return s_currentGameState;
    }

    function getParticipantsLength() external view returns (uint256) {
        return s_participants.length;
    }

    function getFeeIncreaseCounter() external view returns (uint256) {
        return s_feeIncreaseCounter;
    }
}
