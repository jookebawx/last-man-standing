//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Game} from "src/Game.sol";
import {DeployGame} from "script/DeployGame.s.sol";

contract GameUnitTest is Test {
    Game private game;
    DeployGame deployer = new DeployGame();
    address private USER = makeAddr("user");

    function setUp() public {
        game = deployer.deployWithConfig();
    }

    function testInitialState(
        uint256 _gracePeriod,
        uint256 _initialClaimFee,
        uint256 _feeIncreasePercentage,
        uint256 _platformFeePercentage
    ) public {
        game = deployer.deploy(_gracePeriod, _initialClaimFee, _feeIncreasePercentage, _platformFeePercentage);
        assertEq(game.getGracePeriod(), _gracePeriod);
        assertEq(game.getInitialClaimFee(), _initialClaimFee);
        assertEq(game.getFeeIncreasePercentage(), _feeIncreasePercentage);
        assertEq(game.getPlatformFeePercentage(), _platformFeePercentage);
        assertEq(game.getCurrentClaimFee(), _initialClaimFee);
        assertEq(uint256(game.getCurrentGameState()), uint256(Game.gameState.OPEN));
    }

    /*//////////////////////////////////////////////////////////////
                              OWNER TESTS
    //////////////////////////////////////////////////////////////*/
    function testOwnerWithdraw() public {
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        game.claimThrone{value: 0.01 ether}();
        uint256 initialBalance = address(DEFAULT_SENDER).balance;
        console2.log(game.getOwner(), DEFAULT_SENDER);
        vm.startPrank(DEFAULT_SENDER);
        uint256 platformProfitBefore = game.getPlatformProfit();
        game.withdrawPlatformFees();
        uint256 platformProfitAfter = game.getPlatformProfit();
        uint256 finalBalance = address(DEFAULT_SENDER).balance;
        vm.stopPrank();
        assertEq(platformProfitAfter, 0, "Platform profit should be zero after withdrawal");
        assertTrue(
            finalBalance - initialBalance == platformProfitBefore, "Owner should be able to withdraw platform profits"
        );
    }

    function testOnlyOwnerCanWithdrawPlatformFees(address testAddress) public {
        vm.deal(USER, 1 ether);
        vm.prank(USER);
        game.claimThrone{value: 0.01 ether}();
        vm.prank(testAddress);
        vm.expectRevert(Game.Game__UnauthorizedAccess.selector);
        game.withdrawPlatformFees();
    }

    function testupdateGracePeriod(uint256 newGracePeriod, address testAddress) public {
        vm.startPrank(DEFAULT_SENDER);
        game.UpdateGracePeriod(newGracePeriod);
        assertEq(game.getGracePeriod(), newGracePeriod);
        vm.stopPrank();
        vm.prank(testAddress);
        vm.expectRevert(Game.Game__UnauthorizedAccess.selector);
        game.UpdateGracePeriod(newGracePeriod);
    }

    function testupdateInitialClaimFee(uint256 newInitialClaimFee, address testAddress) public {
        vm.startPrank(DEFAULT_SENDER);
        game.UpdateInitialClaimFee(newInitialClaimFee);
        assertEq(game.getInitialClaimFee(), newInitialClaimFee);

        vm.stopPrank();
        vm.prank(testAddress);
        vm.expectRevert(Game.Game__UnauthorizedAccess.selector);
        game.UpdateInitialClaimFee(newInitialClaimFee);
    }

    function testupdateCurrentFeeAfterInitialFeeUpdate(uint256 newInitialClaimFee, address testAddress) public {
        //arrange
        vm.assume(newInitialClaimFee > 0 && newInitialClaimFee < 10 ether && testAddress != USER);

        vm.deal(USER, 1 ether); // Give USER 1 ether
        vm.prank(USER); // Set USER as the caller
        game.claimThrone{value: 0.01 ether}(); // USER claims the throne with 0.01 ether
        vm.deal(testAddress, 1 ether); // Give testAddress 1 ether
        vm.prank(testAddress); // Set testAddress as the caller
        game.claimThrone{value: 0.011 ether}(); // testAddress claims the throne with 0.02 ether
        uint256 claimFeeBeforeUpdate = game.getCurrentClaimFee();
        //act
        vm.startPrank(DEFAULT_SENDER);
        game.UpdateInitialClaimFee(newInitialClaimFee);
        vm.stopPrank();
        uint256 increasePercentage = game.getFeeIncreasePercentage();
        uint256 currentcounter = game.getFeeIncreaseCounter();
        uint256 expectedNewClaimFee = newInitialClaimFee;
        for (uint256 i = 0; i < currentcounter; i++) {
            expectedNewClaimFee = expectedNewClaimFee * (100 + increasePercentage) / 100; // Reset claim fee to initial value
        }
        //assert
        if (claimFeeBeforeUpdate > expectedNewClaimFee) {
            assertEq(
                game.getCurrentClaimFee(),
                claimFeeBeforeUpdate,
                "Current claim fee should not change after initial claim fee update"
            );
        } else {
            assertEq(
                game.getCurrentClaimFee(),
                expectedNewClaimFee,
                "Current claim fee should be updated after initial claim fee update"
            );
        }
    }
    /*//////////////////////////////////////////////////////////////
                             CLAIMANT TEST
    //////////////////////////////////////////////////////////////*/

    function testClaimThrone(address testAddress) public {
        vm.assume(testAddress != USER && testAddress != address(0)); // Ensure testAddress is not USER or zero address
        // Set up initial balance for USER and ensure they can claim the throne
        vm.deal(USER, 1 ether); // Give USER 1 ether
        vm.prank(USER); // Set USER as the caller
        game.claimThrone{value: 0.01 ether}(); // USER claims the throne with 0.01 ether

        uint256 userBalanceBeforePayout = address(USER).balance; // Record USER's balance before the payout

        // Assert that USER is the current King
        assertEq(game.getCurrentKing(), USER, "USER should be the current King");

        // Assert that the claim fee increased by 10% (from 0.01 ether to 0.011 ether)
        assertEq(game.getCurrentClaimFee(), 0.011 ether, "Claim fee should increase by 10% after a claim");

        // Simulate another player (testAddress) claiming the throne
        vm.deal(testAddress, 1 ether); // Give testAddress 1 ether
        vm.prank(testAddress); // Set testAddress as the caller
        game.claimThrone{value: 0.02 ether}(); // testAddress claims the throne with 0.02 ether

        // Assert that testAddress is now the current King
        assertEq(game.getCurrentKing(), testAddress, "testAddress should be the current King");

        uint256 userBalanceAfterPayout = address(USER).balance; // Record USER's balance after the payout

        // Assert that USER received the correct payout (10% of 0.02 ether)
        uint256 expectedPayout = 0.02 ether * 10 / 100; // Calculate expected payout to dethroned King
        assertEq(
            userBalanceAfterPayout - userBalanceBeforePayout,
            expectedPayout,
            "USER should receive payout after being dethroned"
        );

        // Move time past the grace period
        vm.warp(block.timestamp + game.getGracePeriod() + 1); // Advance time past the grace period

        // Try to claim the throne again after the grace period has ended (this should revert)
        vm.prank(USER); // Set USER as the caller again
        vm.expectRevert(Game.Game__GameNotOpen.selector); // Expect the revert with the custom error selector
        game.claimThrone{value: 0.03 ether}(); // USER attempts to claim the throne after grace period ends

        // Assert that the current King is still testAddress (as the game is closed)
        assertEq(game.getCurrentKing(), testAddress, "The current King should still be testAddress after grace period");
    }

    /*//////////////////////////////////////////////////////////////
                               KING TEST
    //////////////////////////////////////////////////////////////*/

    function testDeclareWinner() public {
        vm.expectRevert(Game.Game__GameisOpen.selector);
        game.declareWinner();

        vm.deal(USER, 1 ether);
        vm.prank(USER);
        game.claimThrone{value: 0.01 ether}();
        uint256 winningpot = game.getPot();
        vm.warp(block.timestamp + game.getGracePeriod() + 1); // Move time past the grace period
        game.declareWinner();

        assertTrue(winningpot > 0, "Winning pot should be greater than zero");
        address winner = game.getCurrentKing();
        assertTrue(winner != address(0), "Winner should not be zero address");
        assertEq(uint256(game.getCurrentGameState()), uint256(Game.gameState.CALCULATING));
    }
}
