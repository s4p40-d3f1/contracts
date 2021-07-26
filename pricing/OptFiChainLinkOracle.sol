// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/OptFiOracle.sol";
import "@chainlink/contracts/v0.7/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libs/BokkyPooBahsDateTime/BokkyPooBahsDateTimeLibrary.sol";
import "../libs/PRBMath/PRBMathUD60x18.sol";
import "../libs/PRBMath/PRBMathSD59x18.sol";

contract OptFiChainLinkOracle is OptFiOracle, Ownable{
    using PRBMathUD60x18 for uint256;
    using PRBMathSD59x18 for int256;

    struct Asset{
        address token;
        address oracle;
        uint256[] squaredDailyReturns;
        uint256 sumOfSquaredReturns;
        uint256 previousPrice;
    }

    struct Volatility{
        uint256 volatilityRound;
        uint256 volatilityDays;
        uint256 sumOfSquaredReturns;
        uint256 previousPrice;
        uint256 latestDay;
        uint256 volatility;
    }

    uint256 private _riskFreeRate;
    mapping(address => uint256) private _prices;
    mapping(address => AggregatorV3Interface) private _priceFeeds;
    mapping(address => Volatility) private _volatilities;
    mapping(address => mapping(uint256 => uint256)) squaredDailyReturns;
    
    constructor(uint256 riskFreeRate, Asset[] memory assets) {
        
        _riskFreeRate = riskFreeRate;

        for (uint i = 0; i < assets.length; i++){
            _priceFeeds[assets[i].token] = AggregatorV3Interface(assets[i].oracle);

            Volatility memory volatility = Volatility(1, assets[i].squaredDailyReturns.length, assets[i].sumOfSquaredReturns, assets[i].previousPrice,0,0);
            _volatilities[assets[i].token] = volatility;

            for (uint j = 0; j < assets[i].squaredDailyReturns.length; j++){
                squaredDailyReturns[assets[i].token][i+1] = assets[i].squaredDailyReturns[i];
            }
            
        }
        
    }

    /**
     * Updates data
     */
     function update(address assetToken) external override {
        /*
        * Reads data from oracle
        */
        (,int price,,uint256 latestUpdate,) = _priceFeeds[assetToken].latestRoundData();

        /* 
        * Updates price
        */
        price *= 1e10;
        _prices[assetToken] = uint256(price);
        
        /*
        * Updates volatility
        * Volatility will read just one price per day
        */
        (,, uint256 day) = BokkyPooBahsDateTimeLibrary.timestampToDate(latestUpdate);
        if (day != _volatilities[assetToken].latestDay){
            _calculateVolatility(assetToken);
            _volatilities[assetToken].latestDay = day;
        }

        emit OracleUpdated(assetToken, _prices[assetToken], _riskFreeRate, _volatilities[assetToken].volatility);
    }

    function _calculateVolatility(address assetToken) private{
            /*
            * Calculates squared day return as
            *
            *   r2 = ln( S(i) ÷ S(i -1) ) ^ 2
            *
            * Updates previous price for next calculation round
            */
            uint256 price = _prices[assetToken];
            Volatility storage volatility = _volatilities[assetToken];
            uint256 squaredDayReturn = uint256(int256(price).div(int256(volatility.previousPrice)).ln().powu(2));
            volatility.previousPrice = price;

            /*
            * Keeps sum calculated so it is not needed to iterate the array
            * to calculate this step
            */
            volatility.sumOfSquaredReturns += squaredDayReturn;
            volatility.sumOfSquaredReturns -= squaredDailyReturns[assetToken][volatility.volatilityRound];

            /*
            * Updates the mapping of squared daily returns removing the first element (oldest)
            * while adding latest squared day return to the end
            */
            delete squaredDailyReturns[assetToken][volatility.volatilityRound];
            volatility.volatilityRound++;
            squaredDailyReturns[assetToken][volatility.volatilityRound + volatility.volatilityDays] = squaredDayReturn;
            /*
            * Calculates volatility as
            *
            *   vol = √ (365 * Σ(r2) ÷ periods(days))
            *
            */
            volatility.volatility = volatility.sumOfSquaredReturns.div(volatility.volatilityDays * 1e18).mul(365e18).sqrt();
    }

    /**
     * Returns the latest price, volatility and risk free rate
     */
    function getLatestData(address assetToken) external override view returns (uint256 price, uint256 volatility, uint256 riskFreeRate){
        price = _prices[assetToken];
        volatility = _volatilities[assetToken].volatility;
        riskFreeRate = _riskFreeRate;
    }

    event OracleUpdated(address assetToken, uint256 price, uint256 riskFreeRate, uint256 volatility);
} 