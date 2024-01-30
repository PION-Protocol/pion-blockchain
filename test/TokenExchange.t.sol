// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenExchange.sol";
import "../src/mocks/MockERC20.sol";

contract TokenExchangeTest is Test {
    TokenExchange tokenExchange;
    MockERC20 pion;
    MockERC20 usdt;

    address admin = address(this);
    address treasuryWallet = address(2);
    address developmentWallet = address(3);
    address buyer = address(4);

    uint256 private constant EXCHANGE_RATE = 100;
    uint256 private constant PERCENT = 100;
    uint256 private constant TOKEN_SALE_PERCENT = 80;
    uint256 private constant OP_EX_PERCENT = 20;

    uint256 pionTokenDecimals;
    uint256 usdtTokenDecimals;

    function setUp() public {
        pion = new MockERC20("PION-DUBAI", "PION", 18);
        usdt = new MockERC20("USDT", "USDT", 6);

        pion.mint(address(this), 10000 * EXCHANGE_RATE * 1e18);

        pionTokenDecimals = 10 ** pion.decimals();
        usdtTokenDecimals = 10 ** usdt.decimals();

        tokenExchange = new TokenExchange(address(pion), address(usdt), treasuryWallet, developmentWallet, admin);

        pion.transfer(address(tokenExchange), pion.balanceOf(address(this)));
    }

    function testConstructorInitializesVariablesCorrectly() public {
        assertEq(address(tokenExchange.pion()), address(pion));
        assertEq(address(tokenExchange.usdt()), address(usdt));
        assertEq(tokenExchange.treasuryWallet(), treasuryWallet);
        assertEq(tokenExchange.developmentWallet(), developmentWallet);
        assertEq(tokenExchange.hasRole(tokenExchange.DEFAULT_ADMIN_ROLE(), admin), true);
    }

    function testFailConstructorWithZeroAddress() public {
        new TokenExchange(address(0), address(usdt), treasuryWallet, developmentWallet, admin); // Should fail
        new TokenExchange(address(pion), address(0), treasuryWallet, developmentWallet, admin); // Should fail
        new TokenExchange(address(pion), address(usdt), address(0), developmentWallet, admin); // Should fail
        new TokenExchange(address(pion), address(usdt), treasuryWallet, address(0), admin); // Should fail
        new TokenExchange(address(pion), address(usdt), treasuryWallet, developmentWallet, address(0)); // Should fail
    }

    function testBuyPionSuccess() public {
        uint256 usdtAmount = 1000 * 1e6; // Example USDT amount
        uint256 expectedPionTokens = (usdtAmount * EXCHANGE_RATE * pionTokenDecimals) / usdtTokenDecimals;

        usdt.mint(buyer, usdtAmount);

        vm.startPrank(buyer);

        usdt.approve(address(tokenExchange), usdtAmount);
        tokenExchange.buyPion(usdtAmount);

        vm.stopPrank();

        assertEq(pion.balanceOf(address(buyer)), expectedPionTokens);
        assertEq(usdt.balanceOf(address(buyer)), 0);
        assertEq(usdt.balanceOf(address(treasuryWallet)), 800 * 1e6);
        assertEq(usdt.balanceOf(address(developmentWallet)), 200 * 1e6);
    }

    function testBuyPionInsufficientPionBalance() public {
        uint256 usdtAmount =
            (pion.balanceOf(address(tokenExchange)) * usdtTokenDecimals) / (EXCHANGE_RATE * pionTokenDecimals);
        usdtAmount += 1;

        usdt.mint(buyer, usdtAmount);

        vm.startPrank(buyer);

        usdt.approve(address(tokenExchange), usdtAmount);

        vm.expectRevert(abi.encodeWithSelector(TokenExchange_TokenReserveExhausted.selector, "No tokens left for sale"));
        tokenExchange.buyPion(usdtAmount);

        vm.stopPrank();
    }

    function testBuyPionInsufficientUsdtAmount() public {
        uint256 usdtAmount = 0;

        usdt.mint(buyer, usdtAmount);

        vm.startPrank(buyer);

        usdt.approve(address(tokenExchange), usdtAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenExchange_InsufficientAmount.selector, "Min purchase should atleast be for 1 cent"
            )
        );
        tokenExchange.buyPion(usdtAmount);

        vm.stopPrank();
    }

    function testBuyPionWhenPaused() public {
        uint256 usdtAmount = 1000 * 1e6;

        usdt.mint(buyer, usdtAmount);

        vm.prank(buyer);
        usdt.approve(address(tokenExchange), usdtAmount);

        tokenExchange.pause();

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        tokenExchange.buyPion(usdtAmount);
    }

    function testSuccessfulTokenRetrieval() public {
        uint256 remainingTokens = pion.balanceOf(address(tokenExchange));
        address treasuryAddress = address(0x123);

        tokenExchange.pause();

        vm.prank(admin);
        tokenExchange.retrieveRemainingTokens(treasuryAddress);

        assertEq(pion.balanceOf(treasuryAddress), remainingTokens);
        assertEq(pion.balanceOf(address(tokenExchange)), 0);
    }

    function testTokenRetrivalAccessControl() public {
        address nonAdmin = address(0x123);

        tokenExchange.pause();

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, tokenExchange.DEFAULT_ADMIN_ROLE()
            )
        );
        tokenExchange.retrieveRemainingTokens(nonAdmin);
        vm.stopPrank();
    }

    function testTokenRetrivalWhenNotPaused() public {
        address treasuryAddress = address(0x123);

        vm.expectRevert(Pausable.ExpectedPause.selector);
        tokenExchange.retrieveRemainingTokens(treasuryAddress);
    }

    //Invariant tests

    function testTokenBalanceInvariant() public {
        uint256 initialTotalPion = pion.balanceOf(address(tokenExchange)) + pion.balanceOf(buyer);

        uint256 usdtAmount = 1000 * 1e6;
        usdt.mint(buyer, usdtAmount);

        vm.startPrank(buyer);

        usdt.approve(address(tokenExchange), usdtAmount);
        tokenExchange.buyPion(usdtAmount);

        vm.stopPrank();

        uint256 finalTotalPion = pion.balanceOf(address(tokenExchange)) + pion.balanceOf(buyer);
        assertEq(initialTotalPion, finalTotalPion, "Invariant Violation: Total PION tokens changed unexpectedly.");
    }

    function testUSDTDistributionInvariant() public {
        uint256 initialTotalUSDT =
            usdt.balanceOf(treasuryWallet) + usdt.balanceOf(developmentWallet) + usdt.balanceOf(address(buyer));

        uint256 usdtAmount = 500 * 1e6;
        usdt.mint(address(buyer), usdtAmount);

        vm.startPrank(buyer);

        usdt.approve(address(tokenExchange), usdtAmount);
        tokenExchange.buyPion(usdtAmount);

        vm.stopPrank();

        uint256 finalTotalUSDT =
            usdt.balanceOf(treasuryWallet) + usdt.balanceOf(developmentWallet) + usdt.balanceOf(address(buyer));

        assertEq(finalTotalUSDT - usdtAmount, initialTotalUSDT, "Invariant Violation: USDT distribution mismatch.");
    }

    function testContractStateInvariant() public {
        uint256 usdtAmount = 1000 * 1e6;

        usdt.mint(buyer, usdtAmount);

        vm.prank(buyer);
        usdt.approve(address(tokenExchange), usdtAmount);

        tokenExchange.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(buyer);
        tokenExchange.buyPion(usdtAmount);

        tokenExchange.unpause();
        vm.expectRevert(Pausable.ExpectedPause.selector);
        tokenExchange.retrieveRemainingTokens(treasuryWallet);
    }

    function testAccessControlInvariant() public {
        address nonAdmin = address(5);

        vm.startPrank(nonAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, tokenExchange.DEFAULT_ADMIN_ROLE()
            )
        );
        tokenExchange.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, nonAdmin, tokenExchange.DEFAULT_ADMIN_ROLE()
            )
        );
        tokenExchange.unpause();
        vm.stopPrank();

        tokenExchange.pause();
        tokenExchange.unpause();
    }

    // Fuzz Testing
    function testFuzzBuyPion(uint256 rawUsdtAmount) public {
        uint256 usdtAmount = rawUsdtAmount % 1e18;
        pion.mint(address(tokenExchange), (EXCHANGE_RATE * 10 ** 50));
        usdt.mint(address(buyer), usdtAmount);

        vm.startPrank(buyer);
        usdt.approve(address(tokenExchange), usdtAmount);

        if (((usdtAmount * EXCHANGE_RATE) / usdtTokenDecimals) < 1) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    TokenExchange_InsufficientAmount.selector, "Min purchase should atleast be for 1 cent"
                )
            );
            tokenExchange.buyPion(usdtAmount);
        } else if (pion.balanceOf(address(tokenExchange)) < calculatePionAmount(usdtAmount)) {
            vm.expectRevert(
                abi.encodeWithSelector(TokenExchange_TokenReserveExhausted.selector, "No tokens left for sale")
            );
            tokenExchange.buyPion(usdtAmount);
        } else {
            tokenExchange.buyPion(usdtAmount);

            uint256 treasuryWalletAmount =
                (usdtAmount * TOKEN_SALE_PERCENT * usdtTokenDecimals) / (PERCENT * usdtTokenDecimals);
            uint256 developmentWalletAmount =
                (usdtAmount * OP_EX_PERCENT * usdtTokenDecimals) / (PERCENT * usdtTokenDecimals);

            assertEq(pion.balanceOf(address(buyer)), calculatePionAmount(usdtAmount));
            assertTrue(usdt.balanceOf(address(buyer)) < 100, "USDT balance of buyer should be less than 0.001");
            assertEq(usdt.balanceOf(address(treasuryWallet)), treasuryWalletAmount);
            assertEq(usdt.balanceOf(address(developmentWallet)), developmentWalletAmount);
        }

        vm.stopPrank();
    }

    function calculatePionAmount(uint256 usdtAmount) internal view returns (uint256) {
        return (usdtAmount * EXCHANGE_RATE * pionTokenDecimals) / usdtTokenDecimals;
    }
}
