// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Math.sol";

/**
 * @title SafetyChecks
 * @notice Library for reusable validation and safety check functions
 * @dev Provides risk management validations used across the platform
 */
library SafetyChecks {
    using Math for uint256;

    /// @notice Emitted when a safety check fails (for debugging)
    event SafetyCheckFailed(string reason, uint256 value, uint256 limit);

    /**
     * @notice Check if drawdown is within acceptable limits
     * @param currentBalance Current balance
     * @param highWaterMark Peak balance achieved
     * @param maxDrawdownBps Maximum allowed drawdown in basis points
     * @return bool True if drawdown is acceptable
     */
    function checkDrawdown(
        uint256 currentBalance,
        uint256 highWaterMark,
        uint256 maxDrawdownBps
    ) internal pure returns (bool) {
        if (highWaterMark == 0) return true;
        
        uint256 currentDrawdown = Math.calculateDrawdown(currentBalance, highWaterMark);
        return currentDrawdown <= maxDrawdownBps;
    }

    /**
     * @notice Validate price update is within deviation limits
     * @param oldPrice Previous price
     * @param newPrice New price to validate
     * @param maxDeviationBps Maximum allowed deviation in basis points
     * @return bool True if price change is acceptable
     */
    function validatePriceDeviation(
        uint256 oldPrice,
        uint256 newPrice,
        uint256 maxDeviationBps
    ) internal pure returns (bool) {
        if (oldPrice == 0) return true; // First price update
        
        return Math.isWithinDeviation(oldPrice, newPrice, maxDeviationBps);
    }

    /**
     * @notice Check if exposure is within limits
     * @param currentExposure Current exposure amount
     * @param maxExposure Maximum allowed exposure
     * @return bool True if within limits
     */
    function checkExposureLimit(
        uint256 currentExposure,
        uint256 maxExposure
    ) internal pure returns (bool) {
        return currentExposure <= maxExposure;
    }

    /**
     * @notice Validate position size against balance and limits
     * @param positionSize Requested position size
     * @param availableBalance Available balance for trading
     * @param maxPositionSize Maximum allowed position size
     * @return bool True if position is valid
     */
    function validatePosition(
        uint256 positionSize,
        uint256 availableBalance,
        uint256 maxPositionSize
    ) internal pure returns (bool) {
        if (positionSize == 0) return false;
        if (positionSize > availableBalance) return false;
        if (maxPositionSize > 0 && positionSize > maxPositionSize) return false;
        
        return true;
    }

    /**
     * @notice Check if stop loss has been triggered
     * @param currentPrice Current market price
     * @param stopLossPrice Stop loss trigger price
     * @param isLong True if long position
     * @return bool True if stop loss triggered
     */
    function isStopLossTriggered(
        uint256 currentPrice,
        uint256 stopLossPrice,
        bool isLong
    ) internal pure returns (bool) {
        if (stopLossPrice == 0) return false;
        
        if (isLong) {
            // Long position: stop loss triggers when price falls below stop
            return currentPrice <= stopLossPrice;
        } else {
            // Short position: stop loss triggers when price rises above stop
            return currentPrice >= stopLossPrice;
        }
    }

    /**
     * @notice Check if take profit has been triggered
     * @param currentPrice Current market price
     * @param takeProfitPrice Take profit trigger price
     * @param isLong True if long position
     * @return bool True if take profit triggered
     */
    function isTakeProfitTriggered(
        uint256 currentPrice,
        uint256 takeProfitPrice,
        bool isLong
    ) internal pure returns (bool) {
        if (takeProfitPrice == 0) return false;
        
        if (isLong) {
            // Long position: take profit triggers when price rises above target
            return currentPrice >= takeProfitPrice;
        } else {
            // Short position: take profit triggers when price falls below target
            return currentPrice <= takeProfitPrice;
        }
    }

    /**
     * @notice Validate collateral ratio is sufficient
     * @param collateral Amount of collateral
     * @param exposure Total exposure/position value
     * @param minCollateralRatioBps Minimum required ratio in basis points
     * @return bool True if collateralization is sufficient
     */
    function validateCollateralRatio(
        uint256 collateral,
        uint256 exposure,
        uint256 minCollateralRatioBps
    ) internal pure returns (bool) {
        if (exposure == 0) return true;
        
        // Calculate current ratio: (collateral / exposure) * 10000
        uint256 currentRatio = (collateral * Math.getBpsDenominator()) / exposure;
        
        return currentRatio >= minCollateralRatioBps;
    }

    /**
     * @notice Check if price data is stale
     * @param lastUpdateTime Timestamp of last price update
     * @param heartbeatTimeout Maximum allowed staleness in seconds
     * @return bool True if price is stale
     */
    function isPriceStale(
        uint256 lastUpdateTime,
        uint256 heartbeatTimeout
    ) internal view returns (bool) {
        if (heartbeatTimeout == 0) return false;
        
        return (block.timestamp - lastUpdateTime) > heartbeatTimeout;
    }

    /**
     * @notice Validate trade size meets minimum requirements
     * @param tradeSize Size of the trade
     * @param minTradeSize Minimum allowed trade size
     * @return bool True if trade size is valid
     */
    function validateTradeSize(
        uint256 tradeSize,
        uint256 minTradeSize
    ) internal pure returns (bool) {
        return tradeSize >= minTradeSize;
    }

    /**
     * @notice Check if daily loss limit has been exceeded
     * @param currentDailyLoss Current losses today
     * @param maxDailyLoss Maximum allowed daily loss
     * @return bool True if limit exceeded
     */
    function isDailyLossLimitExceeded(
        uint256 currentDailyLoss,
        uint256 maxDailyLoss
    ) internal pure returns (bool) {
        return currentDailyLoss >= maxDailyLoss;
    }

    /**
     * @notice Validate leverage is within acceptable range
     * @param leverage Requested leverage
     * @param maxLeverage Maximum allowed leverage
     * @return bool True if leverage is valid
     */
    function validateLeverage(
        uint256 leverage,
        uint256 maxLeverage
    ) internal pure returns (bool) {
        if (leverage == 0) return false;
        if (maxLeverage == 0) return true; // No limit
        
        return leverage <= maxLeverage;
    }

    /**
     * @notice Check if sufficient time has passed for cooldown
     * @param lastActionTime Timestamp of last action
     * @param cooldownPeriod Required cooldown in seconds
     * @return bool True if cooldown complete
     */
    function isCooldownComplete(
        uint256 lastActionTime,
        uint256 cooldownPeriod
    ) internal view returns (bool) {
        if (cooldownPeriod == 0) return true;
        
        return (block.timestamp - lastActionTime) >= cooldownPeriod;
    }

    /**
     * @notice Validate evaluation rules are within acceptable parameters
     * @param profitTargetBps Profit target in basis points
     * @param maxDrawdownBps Max drawdown in basis points
     * @return bool True if rules are valid
     */
    function validateEvaluationRules(
        uint256 profitTargetBps,
        uint256 maxDrawdownBps
    ) internal pure returns (bool) {
        // Profit target should be positive and reasonable
        if (profitTargetBps == 0 || profitTargetBps > 10000) return false;
        
        // Max drawdown should be less than 100% and reasonable
        if (maxDrawdownBps == 0 || maxDrawdownBps >= 10000) return false;
        
        return true;
    }

    /**
     * @notice Require drawdown check with custom error
     * @param currentBalance Current balance
     * @param highWaterMark Peak balance achieved
     * @param maxDrawdownBps Maximum allowed drawdown
     */
    function requireDrawdownCheck(
        uint256 currentBalance,
        uint256 highWaterMark,
        uint256 maxDrawdownBps
    ) internal pure {
        require(
            checkDrawdown(currentBalance, highWaterMark, maxDrawdownBps),
            "SafetyChecks: Drawdown limit exceeded"
        );
    }

    /**
     * @notice Require exposure limit check with custom error
     * @param currentExposure Current exposure
     * @param maxExposure Maximum exposure
     */
    function requireExposureLimit(
        uint256 currentExposure,
        uint256 maxExposure
    ) internal pure {
        require(
            checkExposureLimit(currentExposure, maxExposure),
            "SafetyChecks: Exposure limit exceeded"
        );
    }
}
