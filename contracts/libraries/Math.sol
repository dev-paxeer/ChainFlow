// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Math
 * @notice Library for mathematical operations used throughout the prop firm platform
 * @dev Provides safe calculations for PnL, percentages, leverage, TWAP, and basis points
 */
library Math {
    uint256 private constant BPS_DENOMINATOR = 10000; // 100% = 10000 basis points
    uint256 private constant PRICE_DECIMALS = 8; // Price precision (1e8)
    uint256 private constant PERCENTAGE_DECIMALS = 4; // For percentage calculations

    /**
     * @notice Calculate profit/loss for a position
     * @param entryPrice Price at position entry (scaled by 1e8)
     * @param exitPrice Price at position exit (scaled by 1e8)
     * @param size Position size in base units
     * @param isLong True if long position, false if short
     * @return pnl The profit (positive) or loss (negative) as int256
     */
    function calculatePnL(
        uint256 entryPrice,
        uint256 exitPrice,
        uint256 size,
        bool isLong
    ) internal pure returns (int256 pnl) {
        require(entryPrice > 0, "Math: Invalid entry price");
        require(exitPrice > 0, "Math: Invalid exit price");
        require(size > 0, "Math: Invalid size");

        int256 priceDelta;
        
        if (isLong) {
            // Long: profit when price increases
            priceDelta = int256(exitPrice) - int256(entryPrice);
        } else {
            // Short: profit when price decreases
            priceDelta = int256(entryPrice) - int256(exitPrice);
        }

        // PnL = (price change / entry price) * size
        // Using scaled arithmetic to maintain precision
        pnl = (priceDelta * int256(size)) / int256(entryPrice);
    }

    /**
     * @notice Calculate percentage change between two values
     * @param oldValue The original value
     * @param newValue The new value
     * @return percentage The percentage change in basis points (100% = 10000)
     */
    function calculatePercentageChange(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (uint256 percentage) {
        require(oldValue > 0, "Math: Old value cannot be zero");
        
        if (newValue >= oldValue) {
            percentage = ((newValue - oldValue) * BPS_DENOMINATOR) / oldValue;
        } else {
            percentage = ((oldValue - newValue) * BPS_DENOMINATOR) / oldValue;
        }
    }

    /**
     * @notice Calculate drawdown from high water mark
     * @param currentBalance Current balance
     * @param highWaterMark Peak balance achieved
     * @return drawdown Drawdown in basis points (5% = 500)
     */
    function calculateDrawdown(
        uint256 currentBalance,
        uint256 highWaterMark
    ) internal pure returns (uint256 drawdown) {
        require(highWaterMark > 0, "Math: Invalid high water mark");
        
        if (currentBalance >= highWaterMark) {
            return 0;
        }
        
        uint256 loss = highWaterMark - currentBalance;
        drawdown = (loss * BPS_DENOMINATOR) / highWaterMark;
    }

    /**
     * @notice Calculate required margin for a position
     * @param size Position size in base units
     * @param leverage Leverage multiplier (e.g., 10 for 10x)
     * @param price Current asset price (scaled by 1e8)
     * @return margin Required margin amount
     */
    function calculateRequiredMargin(
        uint256 size,
        uint256 leverage,
        uint256 price
    ) internal pure returns (uint256 margin) {
        require(leverage > 0, "Math: Invalid leverage");
        require(price > 0, "Math: Invalid price");
        
        // Margin = (size * price) / leverage
        uint256 positionValue = (size * price) / (10 ** PRICE_DECIMALS);
        margin = positionValue / leverage;
    }

    /**
     * @notice Calculate Time-Weighted Average Price (TWAP)
     * @param prices Array of historical prices
     * @param timestamps Array of corresponding timestamps
     * @param period Time period for TWAP calculation (in seconds)
     * @return twap The time-weighted average price
     */
    function calculateTWAP(
        uint256[] memory prices,
        uint256[] memory timestamps,
        uint256 period
    ) internal view returns (uint256 twap) {
        require(prices.length == timestamps.length, "Math: Array length mismatch");
        require(prices.length >= 2, "Math: Insufficient data points");
        require(period > 0, "Math: Invalid period");

        uint256 currentTime = block.timestamp;
        uint256 startTime = currentTime - period;
        
        uint256 weightedSum = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < prices.length - 1; i++) {
            if (timestamps[i] >= startTime && timestamps[i] < currentTime) {
                uint256 timeWeight = timestamps[i + 1] - timestamps[i];
                weightedSum += prices[i] * timeWeight;
                totalWeight += timeWeight;
            }
        }

        require(totalWeight > 0, "Math: No data in period");
        twap = weightedSum / totalWeight;
    }

    /**
     * @notice Apply basis points to a value
     * @param value The base value
     * @param bps Basis points to apply (100% = 10000)
     * @return result The calculated result
     */
    function applyBasisPoints(
        uint256 value,
        uint256 bps
    ) internal pure returns (uint256 result) {
        result = (value * bps) / BPS_DENOMINATOR;
    }

    /**
     * @notice Calculate liquidation price for a leveraged position
     * @param entryPrice Entry price (scaled by 1e8)
     * @param leverage Position leverage
     * @param isLong True if long position
     * @return liquidationPrice Price at which position gets liquidated
     */
    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        bool isLong
    ) internal pure returns (uint256 liquidationPrice) {
        require(entryPrice > 0, "Math: Invalid entry price");
        require(leverage > 0, "Math: Invalid leverage");

        // Liquidation occurs at ~100% loss of margin
        // For long: liquidation price = entry * (1 - 1/leverage)
        // For short: liquidation price = entry * (1 + 1/leverage)
        
        uint256 priceMovement = entryPrice / leverage;
        
        if (isLong) {
            liquidationPrice = entryPrice - priceMovement;
        } else {
            liquidationPrice = entryPrice + priceMovement;
        }
    }

    /**
     * @notice Check if a value is within acceptable deviation
     * @param oldValue Original value
     * @param newValue New value
     * @param maxDeviationBps Maximum allowed deviation in basis points
     * @return bool True if within acceptable range
     */
    function isWithinDeviation(
        uint256 oldValue,
        uint256 newValue,
        uint256 maxDeviationBps
    ) internal pure returns (bool) {
        if (oldValue == 0) return false;
        
        uint256 deviation = calculatePercentageChange(oldValue, newValue);
        return deviation <= maxDeviationBps;
    }

    /**
     * @notice Calculate profit split between trader and firm
     * @param totalProfit Total profit amount
     * @param traderShareBps Trader's share in basis points (e.g., 8000 for 80%)
     * @return traderAmount Amount for trader
     * @return firmAmount Amount for firm
     */
    function splitProfit(
        uint256 totalProfit,
        uint256 traderShareBps
    ) internal pure returns (uint256 traderAmount, uint256 firmAmount) {
        require(traderShareBps <= BPS_DENOMINATOR, "Math: Invalid share");
        
        traderAmount = applyBasisPoints(totalProfit, traderShareBps);
        firmAmount = totalProfit - traderAmount;
    }

    /**
     * @notice Get basis points denominator
     * @return uint256 The denominator (10000)
     */
    function getBpsDenominator() internal pure returns (uint256) {
        return BPS_DENOMINATOR;
    }
}
