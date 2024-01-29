// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

error TokenExchange_TokenReserveExhausted(string message);
error TokenExchange_InsufficientAmount(string message);
error TokenExchange_InvalidAddress(string message);

contract TokenExchange is Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for ERC20;

    // 1 PION = 0.01 USD
    uint256 private constant EXCHANGE_RATE = 100;
    uint256 private constant PERCENT = 100;
    uint256 private constant TOKEN_SALE_PERCENT = 80;
    uint256 private constant OP_EX_PERCENT = 20;

    ERC20 public immutable pion;
    ERC20 public immutable usdt;
    uint256 public immutable pionTokenDecimals;
    uint256 public immutable usdtTokenDecimals;
    address public immutable treasuryWallet;
    address public immutable developmentWallet;

    event SaleSuccessful(address indexed buyer, uint256 usdtAmount, uint256 pionTokens, uint256 timestamp);
    event TokensRetrived(address treasuryAddress, uint256 pionTokens, uint256 timestamp);

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

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
