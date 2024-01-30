// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title This is the token exchange contract for Pion.
 * @notice This contract allows users to exchange USDT for PION tokens.
 *         Exchange rate: 1 USDT = 100 $PION
 * @dev Utilizes OpenZeppelin's Pausable, AccessControl, and ReentrancyGuard contracts for security
 */
error TokenExchange_TokenReserveExhausted(string message);
error TokenExchange_InsufficientAmount(string message);
error TokenExchange_InvalidAddress(string message);

contract TokenExchange is Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for ERC20;

    // Constants for the exchange calculations
    uint256 private constant EXCHANGE_RATE = 100;
    uint256 private constant PERCENT = 100;
    uint256 private constant TOKEN_SALE_PERCENT = 80;
    uint256 private constant OP_EX_PERCENT = 20;

    // Token references and wallets
    ERC20 public immutable pion;
    ERC20 public immutable usdt;
    uint256 public immutable pionTokenDecimals;
    uint256 public immutable usdtTokenDecimals;
    address public immutable treasuryWallet;
    address public immutable developmentWallet;

    /**
     * @notice Event emitted when a sale of PION tokens is successful
     * @param buyer The address of the buyer
     * @param usdtAmount The amount of USDT spent
     * @param pionTokens The amount of PION tokens purchased
     * @param timestamp The timestamp of the transaction
     */
    event SaleSuccessful(address indexed buyer, uint256 usdtAmount, uint256 pionTokens, uint256 timestamp);

    /**
     * @notice Event emitted when tokens are retrieved from the contract
     *  @param treasuryAddress The address of the treasury receiving the tokens
     *  @param pionTokens The amount of PION tokens retrieved
     *  @param timestamp The timestamp of the transaction
     */
    event TokensRetrived(address treasuryAddress, uint256 pionTokens, uint256 timestamp);

    /**
     * @notice Creates a new TokenExchange contract
     * @dev Grants the DEFAULT_ADMIN_ROLE to the provided admin address
     * @param _pionTokenAddress The address of the PION token contract
     * @param _usdtTokenAddress The address of the USDT token contract
     * @param _treasuryWalletAddress The address of the treasury wallet
     * @param _developmentWalletAddress The address of the development wallet
     * @param _adminAddress The address of the initial admin
     */
    constructor(
        address _pionTokenAddress,
        address _usdtTokenAddress,
        address _treasuryWalletAddress,
        address _developmentWalletAddress,
        address _adminAddress
    ) {
        if (
            _pionTokenAddress == address(0) || _usdtTokenAddress == address(0) || _treasuryWalletAddress == address(0)
                || _developmentWalletAddress == address(0) || _adminAddress == address(0)
        ) {
            revert TokenExchange_InvalidAddress("Please provide a valid address");
        }
        pion = ERC20(_pionTokenAddress);
        usdt = ERC20(_usdtTokenAddress);
        treasuryWallet = _treasuryWalletAddress;
        developmentWallet = _developmentWalletAddress;
        pionTokenDecimals = 10 ** pion.decimals();
        usdtTokenDecimals = 10 ** usdt.decimals();
        _grantRole(DEFAULT_ADMIN_ROLE, _adminAddress);
    }

    /**
     * @notice Allows a user to buy PION tokens with USDT
     * @dev Transfers USDT from the user to the treasury and development wallets, then transfers PION tokens to the user
     * @param usdtAmount The amount of USDT the user wants to spend.
     *        The amount should be included with the decimal value e.x. 1 USDT (6 decimals) = 1000000 usdtAmount
     */
    function buyPion(uint256 usdtAmount) external whenNotPaused nonReentrant {
        if ((usdtAmount * EXCHANGE_RATE) / usdtTokenDecimals > 0) {
            uint256 pionTokens = ((usdtAmount * EXCHANGE_RATE * pionTokenDecimals) / usdtTokenDecimals);

            if (pion.balanceOf(address(this)) >= pionTokens) {
                uint256 treasuryWalletAmount =
                    (usdtAmount * TOKEN_SALE_PERCENT * usdtTokenDecimals) / (PERCENT * usdtTokenDecimals);
                uint256 developmentWalletAmount =
                    (usdtAmount * OP_EX_PERCENT * usdtTokenDecimals) / (PERCENT * usdtTokenDecimals);

                usdt.safeTransferFrom(msg.sender, treasuryWallet, treasuryWalletAmount);
                usdt.safeTransferFrom(msg.sender, developmentWallet, developmentWalletAmount);
                pion.safeTransfer(msg.sender, pionTokens);

                emit SaleSuccessful(msg.sender, usdtAmount, pionTokens, block.timestamp);
            } else {
                revert TokenExchange_TokenReserveExhausted("No tokens left for sale");
            }
        } else {
            revert TokenExchange_InsufficientAmount("Min purchase should atleast be for 1 cent");
        }
    }

    /**
     * @notice Allows the admin to retrieve remaining PION tokens from the contract
     * @dev Can only be called when the contract is paused and by an account with the DEFAULT_ADMIN_ROLE
     * @param treasuryAddress The address where the remaining PION tokens will be sent
     */
    function retrieveRemainingTokens(address treasuryAddress)
        external
        whenPaused
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint256 remainingTokens = pion.balanceOf(address(this));
        pion.safeTransfer(treasuryAddress, remainingTokens);
        emit TokensRetrived(treasuryAddress, remainingTokens, block.timestamp);
    }

    /**
     * @notice Pauses the contract, disabling token buys
     * @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, enabling token buys
     * @dev Can only be called by an account with the DEFAULT_ADMIN_ROLE
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
