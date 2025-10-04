// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Math.sol";
import "./SafetyChecks.sol";

/**
 * @title PositionManager
 * @notice Library for managing trading positions and calculations
 * @dev Provides position lifecycle management and validation
 */
library PositionManager {
    using Math for uint256;
    using SafetyChecks for uint256;

    /// @notice Position data structure
    struct Position {
        uint256 positionId;
        address oracle;
        uint256 entryPrice;
        uint256 size;
        bool isLong;
        uint256 collateral;
        uint256 stopLoss;
        uint256 takeProfit;
        uint256 openTime;
        bool isOpen;
    }

    /// @notice Position validation parameters
    struct PositionParams {
        uint256 maxPositionSize;
        uint256 maxLeverage;
        uint256 minTradeSize;
        uint256 requiredStopLoss; // If true, stop loss is mandatory
    }

    /**
     * @notice Calculate required margin for opening a position
     * @param size Position size
     * @param price Entry price
     * @param leverage Leverage multiplier
     * @return margin Required margin amount
     */
    function calculateRequiredMargin(
        uint256 size,
        uint256 price,
        uint256 leverage
    ) internal pure returns (uint256 margin) {
        return Math.calculateRequiredMargin(size, leverage, price);
    }

    /**
     * @notice Calculate current PnL for a position
     * @param position Position data
     * @param currentPrice Current market price
     * @return pnl Profit or loss (can be negative)
     */
    function calculatePositionPnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256 pnl) {
        require(position.isOpen, "PositionManager: Position not open");
        
        return Math.calculatePnL(
            position.entryPrice,
            currentPrice,
            position.size,
            position.isLong
        );
    }

    /**
     * @notice Calculate liquidation price for a position
     * @param entryPrice Entry price
     * @param size Position size
     * @param collateral Collateral amount
     * @param isLong True if long position
     * @return liquidationPrice Price at which position gets liquidated
     */
    function calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 size,
        uint256 collateral,
        bool isLong
    ) internal pure returns (uint256 liquidationPrice) {
        require(size > 0, "PositionManager: Invalid size");
        require(collateral > 0, "PositionManager: Invalid collateral");
        
        // Calculate effective leverage
        uint256 positionValue = (size * entryPrice) / 1e8;
        uint256 leverage = positionValue / collateral;
        
        return Math.calculateLiquidationPrice(entryPrice, leverage, isLong);
    }

    /**
     * @notice Check if position should be liquidated
     * @param position Position data
     * @param currentPrice Current market price
     * @return bool True if position should be liquidated
     */
    function shouldLiquidate(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (bool) {
        if (!position.isOpen) return false;
        
        uint256 liqPrice = calculateLiquidationPrice(
            position.entryPrice,
            position.size,
            position.collateral,
            position.isLong
        );
        
        if (position.isLong) {
            return currentPrice <= liqPrice;
        } else {
            return currentPrice >= liqPrice;
        }
    }

    /**
     * @notice Check if stop loss has been triggered
     * @param position Position data
     * @param currentPrice Current market price
     * @return bool True if stop loss triggered
     */
    function checkStopLoss(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (bool) {
        return SafetyChecks.isStopLossTriggered(
            currentPrice,
            position.stopLoss,
            position.isLong
        );
    }

    /**
     * @notice Check if take profit has been triggered
     * @param position Position data
     * @param currentPrice Current market price
     * @return bool True if take profit triggered
     */
    function checkTakeProfit(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (bool) {
        return SafetyChecks.isTakeProfitTriggered(
            currentPrice,
            position.takeProfit,
            position.isLong
        );
    }

    /**
     * @notice Validate position parameters before opening
     * @param size Position size
     * @param stopLoss Stop loss price
     * @param availableBalance Available balance
     * @param params Position validation parameters
     * @return bool True if valid
     */
    function validateNewPosition(
        uint256 size,
        uint256 stopLoss,
        uint256 availableBalance,
        PositionParams memory params
    ) internal pure returns (bool) {
        // Check minimum trade size
        if (!SafetyChecks.validateTradeSize(size, params.minTradeSize)) {
            return false;
        }
        
        // Check maximum position size
        if (!SafetyChecks.validatePosition(size, availableBalance, params.maxPositionSize)) {
            return false;
        }
        
        // Check stop loss requirement
        if (params.requiredStopLoss > 0 && stopLoss == 0) {
            return false;
        }
        
        return true;
    }

    /**
     * @notice Validate stop loss price is reasonable
     * @param entryPrice Entry price
     * @param stopLoss Stop loss price
     * @param isLong True if long position
     * @param maxStopLossDistanceBps Max distance in basis points
     * @return bool True if stop loss is valid
     */
    function validateStopLoss(
        uint256 entryPrice,
        uint256 stopLoss,
        bool isLong,
        uint256 maxStopLossDistanceBps
    ) internal pure returns (bool) {
        if (stopLoss == 0) return false;
        
        // For long: stop loss should be below entry
        // For short: stop loss should be above entry
        if (isLong && stopLoss >= entryPrice) return false;
        if (!isLong && stopLoss <= entryPrice) return false;
        
        // Check distance is not too large
        uint256 distance = isLong 
            ? Math.calculatePercentageChange(stopLoss, entryPrice)
            : Math.calculatePercentageChange(entryPrice, stopLoss);
            
        return distance <= maxStopLossDistanceBps;
    }

    /**
     * @notice Calculate position value at current price
     * @param position Position data
     * @param currentPrice Current market price
     * @return value Current position value
     */
    function calculatePositionValue(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (uint256 value) {
        require(position.isOpen, "PositionManager: Position not open");
        
        value = (position.size * currentPrice) / 1e8;
    }

    /**
     * @notice Calculate position's return on investment
     * @param position Position data
     * @param currentPrice Current market price
     * @return roi Return on investment in basis points
     */
    function calculateROI(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (int256 roi) {
        require(position.collateral > 0, "PositionManager: Invalid collateral");
        
        int256 pnl = calculatePositionPnL(position, currentPrice);
        
        // ROI = (PnL / Collateral) * 10000
        roi = (pnl * int256(Math.getBpsDenominator())) / int256(position.collateral);
    }

    /**
     * @notice Get position health score (0-100)
     * @param position Position data
     * @param currentPrice Current market price
     * @return health Health score (100 = healthy, 0 = near liquidation)
     */
    function getPositionHealth(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (uint256 health) {
        if (!position.isOpen) return 0;
        
        uint256 liqPrice = calculateLiquidationPrice(
            position.entryPrice,
            position.size,
            position.collateral,
            position.isLong
        );
        
        uint256 entryToLiq;
        uint256 currentToLiq;
        
        if (position.isLong) {
            entryToLiq = position.entryPrice - liqPrice;
            if (currentPrice <= liqPrice) return 0;
            currentToLiq = currentPrice - liqPrice;
        } else {
            entryToLiq = liqPrice - position.entryPrice;
            if (currentPrice >= liqPrice) return 0;
            currentToLiq = liqPrice - currentPrice;
        }
        
        if (entryToLiq == 0) return 100;
        
        // Health = (current distance to liq / entry distance to liq) * 100
        health = (currentToLiq * 100) / entryToLiq;
        if (health > 100) health = 100;
    }

    /**
     * @notice Create a new position struct
     * @param positionId Unique position ID
     * @param oracle Price oracle address
     * @param entryPrice Entry price
     * @param size Position size
     * @param isLong True if long position
     * @param collateral Collateral amount
     * @param stopLoss Stop loss price
     * @param takeProfit Take profit price
     * @return position New position struct
     */
    function createPosition(
        uint256 positionId,
        address oracle,
        uint256 entryPrice,
        uint256 size,
        bool isLong,
        uint256 collateral,
        uint256 stopLoss,
        uint256 takeProfit
    ) internal view returns (Position memory position) {
        position = Position({
            positionId: positionId,
            oracle: oracle,
            entryPrice: entryPrice,
            size: size,
            isLong: isLong,
            collateral: collateral,
            stopLoss: stopLoss,
            takeProfit: takeProfit,
            openTime: block.timestamp,
            isOpen: true
        });
    }

    /**
     * @notice Close a position and calculate final PnL
     * @param position Position to close
     * @param exitPrice Exit price
     * @return pnl Final profit or loss
     */
    function closePosition(
        Position memory position,
        uint256 exitPrice
    ) internal pure returns (int256 pnl) {
        require(position.isOpen, "PositionManager: Position not open");
        
        pnl = Math.calculatePnL(
            position.entryPrice,
            exitPrice,
            position.size,
            position.isLong
        );
    }
}
