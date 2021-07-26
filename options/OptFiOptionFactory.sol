// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./OptFiOption.sol";
import "./lib/OptFiOptionLibrary.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Implementation of the Option Factory used by the Option Pool
 * @author s4p40-d3fi
 * @dev This contract implements lifecycle management of the option contracts
 * managed (written and bought) by the liquidity pool
 */

 contract OptFiOptionFactory is Ownable, ReentrancyGuard{

    OptFiOption private _optionImplementation;
    mapping(bytes32 => OptFiOption) private _options;

    constructor()
    {
        _optionImplementation = new OptFiOption();
        _optionImplementation.initializeImplementation();
    }

    /**
     * @dev Gets existing option contract to buy operation. Creates if it does not exist.
     * @param optionType The type of the option
     * @param optionAssetToken The underlying asset token of the option
     * @param strikes The strikes of the option
     * @param expiration The expiration UTC datetime of the option
     * @param assetPrice The latest asset price for strike validation
     * @return The option contract
     */

    function getOptionToBuy(OptFiOption.OptFiOptionType optionType, IERC20Metadata optionAssetToken, uint256[] memory strikes, uint256 expiration, uint256 assetPrice) external onlyOwner returns (OptFiOption) {
        /*
        * Strike validation
        */
        OptFiOptionLibrary.validateStrikes(optionType, strikes, assetPrice);
        
        /*
        * Gets option contract
        */
        bytes32 optionId = OptFiOptionLibrary.createId(optionType, optionAssetToken, strikes, expiration);
        
        if (address(_options[optionId]) == address(0)){
            /*
            * Expiration validation
            */
            OptFiOptionLibrary.validateExpiration(expiration);

            /*
            * Sets name and symbol for the option
            */
            string memory name = OptFiOptionLibrary.createName(optionType, optionAssetToken, strikes, expiration);
            string memory symbol = OptFiOptionLibrary.createSymbol(optionType, optionAssetToken, strikes, expiration);

            /*
            * Clones and initializes contract
            */
            _options[optionId] = OptFiOption(Clones.clone(address(_optionImplementation)));
            _options[optionId].initialize(name, symbol, optionType, optionAssetToken, optionId, strikes, expiration, this.owner());

            emit OptionCreated(optionId, _options[optionId]);
        }
        
        return _options[optionId];

    }

     /**
     * @dev Gets existing option contract to sell operation.
     * @param optionType The type of the option
     * @param optionAssetToken The underlying asset token of the option
     * @param strikes The strikes of the option
     * @param expiration The expiration UTC datetime of the option
     * @return The option contract
     */

    function getOptionToSell(OptFiOption.OptFiOptionType optionType, IERC20Metadata optionAssetToken, uint256[] memory strikes, uint256 expiration) external view onlyOwner returns (OptFiOption) {
        /*
        * Gets option contract
        */
        bytes32 optionId = OptFiOptionLibrary.createId(optionType, optionAssetToken, strikes, expiration);
        require(address(_options[optionId]) != address(0),"Option not found");
        return _options[optionId];
    }

    /**
     * @dev Emitted when a call contract is created.
     * @param optionId The unique identifier for this option.
     * @param option The call contract created.
     */
    event OptionCreated(bytes32 optionId, OptFiOption option);

 }