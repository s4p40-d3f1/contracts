// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface OptFiOracle {

    function update(address assetToken) external;
    function getLatestData(address assetToken) external view returns (uint256 price, uint256 volatility, uint256 riskFreeRate);

} 