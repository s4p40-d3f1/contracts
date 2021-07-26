// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../OptFiOption.sol";
import "../../libs/BokkyPooBahsDateTime/BokkyPooBahsDateTimeLibrary.sol";
import "../../libs/PRBMath/PRBMathUD60x18.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

library OptFiOptionLibrary {
    using PRBMathUD60x18 for uint256;

    function createId(OptFiOption.OptFiOptionType optionType, IERC20Metadata optionAssetToken, uint256[] memory strikes, uint256 expiration) internal pure returns(bytes32) {
        return keccak256(abi.encode(optionType, optionAssetToken, strikes, expiration));
    }

    function createName(OptFiOption.OptFiOptionType optionType, IERC20Metadata optionAssetToken, uint256[] memory strikes, uint256 expiration) internal view returns (string memory){
        string[4] memory typeNames = ["Call", "Spread", "Butterfly","Put"];        
        string memory strike;
        for (uint8 i = 0; i < strikes.length; i++) {
            if (i > 0){ strike = string(abi.encodePacked(strike, "-")); }
            strike = string(abi.encodePacked(strike, OptFiOptionLibrary.uint2str(strikes[i]/1e18)));
        }
        (uint year ,uint month, uint day) = BokkyPooBahsDateTimeLibrary.timestampToDate(expiration);
        return string(abi.encodePacked("OptFi ",typeNames[uint256(optionType)], ": ", optionAssetToken.symbol(), " [", strike, "] ", OptFiOptionLibrary.uint2str(year),"-",OptFiOptionLibrary.uint2str(month),"-",OptFiOptionLibrary.uint2str(day)));
    }

    function createSymbol(OptFiOption.OptFiOptionType optionType, IERC20Metadata optionAssetToken, uint256[] memory strikes, uint256 expiration) internal view returns (string memory){
        string[4] memory typeNames = ["C", "S", "B", "P"]; 
        string[12] memory expiration01codes = ["A", "C", "E",  "G",  "I",  "K",  "M",  "O", "Q",  "S", "U", "X"];
        string[12] memory expiration15codes = ["B", "D", "F",  "H",  "J",  "L",  "N",  "P", "R",  "T", "V", "Y"];
        ( ,uint month, uint day) = BokkyPooBahsDateTimeLibrary.timestampToDate(expiration);
        string memory monthCode;
        if (day == 1){
            monthCode = expiration01codes[month - 1];
        } else if (day == 15) {
            monthCode = expiration15codes[month - 1];
        }
        return string(abi.encodePacked(optionAssetToken.symbol(), monthCode, OptFiOptionLibrary.uint2str(strikes[0]/1e18), typeNames[uint256(optionType)]));
    }

    function _validateStrike(uint256 strike, uint256 assetPrice) private pure {

        uint16[75] memory baseStrikes = [100, 105, 110, 115, 120, 125, 130, 135, 140, 145, 150, 155, 160, 165, 170, 175, 180, 185, 190, 195, 200, 210, 220, 230, 240, 250, 260, 270, 280, 290, 300, 310, 320, 330, 340, 350, 360, 370, 380, 390, 400, 410, 420, 430, 440, 450, 460, 470, 480, 490, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 720, 740, 760, 780, 800, 820, 840, 860, 880, 900, 920, 940, 960, 980];

        //Validate strike is between the limits
        uint256 lowerLimit = assetPrice.mul(8e17);
        uint256 upperLimit = assetPrice.mul(13e17);
        require(strike >= lowerLimit && strike <= upperLimit,"Strike out of limits");

        //Validate strike digits
        uint8 digits = _getDigits(strike);
        require(digits > 3, "Strike digits < 3");
 
        //Validate strike is valid
        digits -= 3;
        for (uint8 i = 0; i < baseStrikes.length; i++) {
            if (strike == baseStrikes[i]*10**digits){ return; }
        }
        revert("Invalid strike");
        
    }

    function validateStrikes(OptFiOption.OptFiOptionType optionType, uint256[] memory strikes, uint256 assetPrice) internal pure {
        /*
        * Limiting the size of the strikes array
        */
        require(strikes.length < 5,"Strikes > 5");

        /*
        * Validating allowed strikes
        */
        for (uint256 i = 0; i < strikes.length; i++) {
            _validateStrike(strikes[i], assetPrice);
        }

        /*
        * Validation for spread options
        */
        if (optionType == OptFiOption.OptFiOptionType.SPREAD){
            require(strikes.length == 2,"Spread: 2 strikes required");
            require(strikes[0] < strikes[1],"Spread: 2nd > 1st required");
        }

        /*
        * Validation for butterfly options
        */
        if (optionType == OptFiOption.OptFiOptionType.BUTTERFLY){
            require(strikes.length == 3,"Butterfly: 3 strikes required");
            require(strikes[0] < strikes[1],"Butterfly: 2nd > 1st required");
            require(strikes[1] < strikes[2],"Butterfly: 3rd > 2nd required");
            require((strikes[1] - strikes[0]) == (strikes[2] - strikes[1]), "Same spread strikes required");
        }
    }
    
    function validateExpiration(uint256 expiration) internal view {
        require(expiration > block.timestamp, "Expiration in the past");
        require(expiration < block.timestamp + 60 days, "Expiration after 60 days");
        (, , uint day, uint hour, uint minute, uint second) = BokkyPooBahsDateTimeLibrary.timestampToDateTime(expiration);
        require((day == 1 || day == 15), "Day must be 1 or 15.");
        require((hour == 23 && minute == 59 && second == 59), "Time must be 23:59:59");
    }

    function _getDigits(uint256 number) private pure returns (uint8 digits) {
        while (number != 0) {
            number /= 10;
            digits++;
        }
    }

    function uint2str(uint256 _i) internal pure returns (string memory str)
    {
        if (_i == 0){ return "0"; }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0){
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }
}