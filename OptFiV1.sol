// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./pool/OptFiPool.sol";
import "./pool/OptFiPoolFactory.sol";
import "./options/OptFiOption.sol";
import "./options/OptFiOptionFactory.sol";
import "./pricing/lib/OptFiBlack76Library.sol";
import "./pricing/OptFiChainLinkOracle.sol";

import "./libs/PRBMath/PRBMathUD60x18.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Implementation of the OptFi - Descentralized Options Protocol
 * @author s4p40-d3fi
 * @dev This contract coordinates the interaction between market participants and the liquidity
 * pool allowing for buyers and sellers to trade options
 */

contract OptFiV1 is Ownable, ReentrancyGuard {
    using PRBMathUD60x18 for uint256;

    OptFiOracle public _oracle;
    OptFiPoolFactory public _poolFactory;
    OptFiOptionFactory public _optionsFactory;

    address _optFiAddress;
    uint256 constant protocolFee = 1e16;
    
    constructor(OptFiPoolFactory poolFactory_, OptFiOracle oracle_, address optFiAddress){
        _poolFactory = poolFactory_;
        _oracle = oracle_;
        _optFiAddress = optFiAddress;
        _optionsFactory = new OptFiOptionFactory();
    }

    /**
    * @dev This function is called to buy options from the pool.
    */
    function buy(OptFiOption.OptFiOptionType optionType, IERC20Metadata assetToken, IERC20Metadata strikeToken, uint256[] memory strikes, uint256 expiration, uint256 amount, uint256 maxPremiumPayment) external nonReentrant {
        /*
        * Performs update and validation of oracle data
        */
        _oracle.update(address(assetToken));
        (uint256 assetPrice,,) = _oracle.getLatestData(address(assetToken));

        /*
        * Gets corresponding pool and validates amount requested can be fulfilled
        */
        OptFiPool pool = choosePool(optionType, assetToken, strikeToken, _poolFactory);

        /*
        * Gets requested option from factory
        * If the contract does not exist, try to create it
        */
        OptFiOption option = _optionsFactory.getOptionToBuy(optionType, assetToken, strikes, expiration, assetPrice);

        /*
        * Calculate option price
        * Asks price maker to calculate call price
        */
        uint256 optionPrice = OptFiBlack76Library.calculatePrice(option, _oracle);

        /* 
        * Calculates collateral amount according to option type ans strikes
        */
        uint256 collateralAmount = calculateCollateralAmount(optionType, strikes, amount);

        /*
        * Pool receives premium, collect fees and lock funds
        */
        pool.receivePremium(msg.sender, amount, collateralAmount, expiration, optionPrice, _optFiAddress, protocolFee, maxPremiumPayment);

        /*
        * Mint options to the buyer
        * New fungible options are minted to the buyer as ERC20 tokens
        */
        option.mint(msg.sender, amount);

        emit OptionBought(msg.sender, option, amount);
        
    }

    /**
    * @dev This function is called to sell options to the pool.
    */
    function sell(OptFiOption.OptFiOptionType optionType, IERC20Metadata assetToken, IERC20Metadata strikeToken, uint256[] memory strikes, uint256 expiration, uint256 amount, uint256 minPremiumPayment) external nonReentrant{
        /*
        * Gets corresponding pool and validates amount requested can be fulfilled
        */
        OptFiPool pool = choosePool(optionType, assetToken, strikeToken, _poolFactory);

        /*
        * Gets requested option from factory
        * If the contract does not exist, the factory will try to create it
        */
        OptFiOption option = _optionsFactory.getOptionToSell(optionType, assetToken, strikes, expiration);

        /*
        * Performs update and validation of oracle data
        */
        _oracle.update(address(option.getAssetToken()));

        /*
        * Calculate option price
        * Asks price maker to calculate call price
        */
        uint256 optionPrice = OptFiBlack76Library.calculatePrice(option, _oracle);

        /* 
        * Asks pool to calculate pool fee:
        */
        uint256 collateralAmount = calculateCollateralAmount(optionType, strikes, amount);
        

        /*
        * Transfer premium to the pool and lock funds
        */
        pool.payPremium(msg.sender, amount, collateralAmount, expiration, optionPrice, _optFiAddress, protocolFee, minPremiumPayment);

        /*
        * Mint calls to the buyer
        * New fungible calls are minted as ERC20 tokens and sent to the buyer
        */
        option.burn(msg.sender, amount);

        emit OptionSold(msg.sender, option, amount);
    }

    function calculateCollateralAmount(OptFiOption.OptFiOptionType optionType, uint256[] memory strikes, uint256 amount) private pure returns(uint256 poolAmount)  {
        if (optionType == OptFiOption.OptFiOptionType.CALL || optionType == OptFiOption.OptFiOptionType.PUT){
            poolAmount = amount;
        } else if (optionType == OptFiOption.OptFiOptionType.SPREAD || optionType == OptFiOption.OptFiOptionType.BUTTERFLY){
            poolAmount = (strikes[1] - strikes[0]).mul(amount);
        }
    }

    /*
    * Gets corresponding pool
    */
    function choosePool(OptFiOption.OptFiOptionType optionType, IERC20Metadata assetToken, IERC20Metadata strikeToken, OptFiPoolFactory poolFactory) private view returns(OptFiPool pool) {
        if (optionType == OptFiOption.OptFiOptionType.CALL){
            pool = poolFactory.getPool(assetToken);
        }
        else if (optionType == OptFiOption.OptFiOptionType.SPREAD || optionType == OptFiOption.OptFiOptionType.BUTTERFLY || optionType == OptFiOption.OptFiOptionType.PUT){
            pool = poolFactory.getPool(strikeToken);
        }
        require(address(pool) != address(0), "Pool not found");
    }

    event OptionBought(address indexed buyer, OptFiOption indexed option, uint256 amount);
    event OptionSold(address indexed seller, OptFiOption indexed option, uint256 amount);

    fallback() external {}

}