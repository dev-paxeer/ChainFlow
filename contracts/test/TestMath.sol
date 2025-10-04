// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../libraries/Math.sol";

/**
 * @title TestMath
 * @notice Wrapper contract to test Math library functions
 */
contract TestMath {
    using Math for uint256;

    function calculatePnL(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 size,
        bool isLong
    ) external pure returns (int256) {
        return Math.calculatePnL(entryPrice, exitPrice, size, isLong);
    }

    function calculatePercentageChange(
        uint256 oldValue,
        uint256 newValue
    ) external pure returns (uint256) {
        return Math.calculatePercentageChange(oldValue, newValue);
    }

    function calculateDrawdown(
        uint256 currentBalance,
        uint256 highWaterMark
    ) external pure returns (uint256) {
        return Math.calculateDrawdown(currentBalance, highWaterMark);
    }

    function calculateRequiredMargin(
        uint256 size,
        uint256 leverage,
        uint256 price
    ) external pure returns (uint256) {
        return Math.calculateRequiredMargin(size, leverage, price);
    }

    function calculateTWAP(
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256 period
    ) external view returns (uint256) {
        return Math.calculateTWAP(prices, timestamps, period);
    }

    function applyBasisPoints(
        uint256 value,
        uint256 bps
    ) external pure returns (uint256) {
        return Math.applyBasisPoints(value, bps);
    }

    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        bool isLong
    ) external pure returns (uint256) {
        return Math.calculateLiquidationPrice(entryPrice, leverage, isLong);
    }

    function isWithinDeviation(
        uint256 oldValue,
        uint256 newValue,
        uint256 maxDeviationBps
    ) external pure returns (bool) {
        return Math.isWithinDeviation(oldValue, newValue, maxDeviationBps);
    }

    function splitProfit(
        uint256 totalProfit,
        uint256 traderShareBps
    ) external pure returns (uint256 traderAmount, uint256 firmAmount) {
        return Math.splitProfit(totalProfit, traderShareBps);
    }

    function getBpsDenominator() external pure returns (uint256) {
        return Math.getBpsDenominator();
    }
}
