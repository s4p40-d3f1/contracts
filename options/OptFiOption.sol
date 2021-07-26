// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Contract of the OptFi Options
 * @author s4p40-d3fi
 * @dev This  contract is implemeted for the options tradeable by the liquidity pool
 * The option contract is a ERC20 in order for the options to be tokenized and freely traded
 */

contract OptFiOption is ERC20, Initializable{

    enum OptFiOptionType {CALL, SPREAD, BUTTERFLY, PUT}

    address private _owner;

    string private _name;
    string private _symbol;
    
    bytes32 private _optionId;
    OptFiOptionType _optionType;
    IERC20Metadata _optionAssetToken;
    uint256 private _expiration;
    uint256[] private _strikes;

    constructor () ERC20("OptFi Option", "OptFiOption") {}

    /**
    * @dev Option implementation initialization.
    *
    * Function used by option factory constructor to initialize contract implementation 
    *
    **/
    function initializeImplementation() external initializer {}

    function initialize(string memory name_, string memory symbol_, OptFiOptionType optionType_, IERC20Metadata optionAssetToken_, bytes32 optionId_, uint256[] memory strikes_, uint256 expiration_, address owner_) external initializer{
        
        require(bytes(name_).length > 0,"Option: Missing name");
        require(bytes(symbol_).length > 0,"Option: Missing symbol");
        require(optionId_.length > 0,"Option: Missing ID");
        require(expiration_ > block.timestamp, "Option: Expiration must be in the future");
        require(strikes_.length > 0,"Option: Missing strikes");
        
        for (uint256 i = 0; i < strikes_.length; i++) {
            require(strikes_[i] > 0, "Option: Strike must be > 0.");
        }
        
        _name = name_;
        _symbol = symbol_;
        _optionId = optionId_;
        _optionType = optionType_;
        _optionAssetToken = optionAssetToken_;
        _expiration = expiration_;
        _strikes = strikes_;

        _owner = owner_;
    }

    function mint(address to, uint256 amount) external {
        require(_owner == _msgSender(), "Option: caller is not the owner");
        require(amount > 0, "Option: Mint amount is zero");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(_owner == _msgSender(), "Option: caller is not the owner");
        require(amount > 0, "Option: Burn amount is zero");
        _burn(from, amount);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function getType() external view returns(OptFiOptionType){
        return _optionType;
    }

    function getExpiration() external view returns(uint256) {
        return _expiration;
    }

    function getStrike(uint256 index) external view returns(uint256) {
        return _strikes[index];
    }

    function getStrikes() external view returns(uint256[] memory) {
        return _strikes;
    }

    function getAssetToken() external view returns(IERC20Metadata) {
        return _optionAssetToken;
    }

    function getOptionData() external view returns(string memory optionName, string memory optionSymbol, OptFiOptionType optionType, uint256 expiration, uint256[] memory strikes, IERC20Metadata assetToken){
        optionName = _name;
        optionSymbol = _symbol;
        optionType = _optionType;
        expiration = _expiration;
        strikes = _strikes;
        assetToken = _optionAssetToken;
    }

    fallback() external {}

} 