// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./OptFiPoolToken.sol";

import "../libs/PRBMath/PRBMathUD60x18.sol";

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OptFiPool is Initializable, ReentrancyGuard{
  using PRBMathUD60x18 for uint256;
  
  struct LockedBalance{
    uint256 expiration;
    uint256 balance;
  }
  LockedBalance[] private _lockedBalances;

  address private _owner;
  uint256 private _lockedBalance;
  IERC20Metadata private _token;
  OptFiPoolToken private _poolShareToken;
  OptFiPoolToken private _poolWithdrawToken;
  
  mapping (address => uint256) private _postdatedWithdrawAllowances;
  
  constructor() {}

  /**
  * @dev Pool implementation initialization.
  *
  * Function used by pool factory constructor to initialize contract implementation 
  *
  **/
  function initializeImplementation() external initializer {}

  /**
  * @dev Pool initialization.
  *
  * During pool initialization two ERC20 tokens are deployed:
  *   Pool Share Token (PST-symbol): The token given to liquidity providers representing  
  *   their share in the pool resources;
  *   Pool Withdraw Token (PWT-symbol): The token given to liquidity providers representing 
  *   their share in postdate withdraws.
  **/
  function initialize(IERC20Metadata token_,  address owner_, OptFiPoolToken poolShareToken_, OptFiPoolToken poolWithdrawToken_) external initializer {
    
    /*
    * Only tokens with 18 decimals are allowed
    */
    require(token_.decimals() == 18, "OptFi Pool only accepts 18 decimals tokens.");
    
    _token = token_;
    _owner = owner_;

    /*
    * Pool token (ERC20) contracts are created
    */
    _poolShareToken = poolShareToken_;
    _poolWithdrawToken = poolWithdrawToken_;

    emit PoolInitialized(_token, _poolShareToken, _poolWithdrawToken, _owner);
    
  }

  /**
  * @dev This function calculates the liquidity fee charged by the pool.
  *
  * This fee is meant to be charged over the option amount as a payment for reducing
  * the liquidity of the pool. 
  *
  * The central idea is that this function allows the pool to self adjust the price for liquidity
  * attracting LPs as the price rises until they reach equilibrium between supply/demand.
  *
  * The formula applied is:
  *
  *   Liquidity Fee(%) = (Unlocked Balance ÷ Locked Balance) ÷ 100
  *
  * The example below shows the fee values for pool utilization:
  *
  * Utilization  |  Fee
  *          1%  | 0,010%
  *         10%  | 0,111%
  *         20%  | 0,250%
  *         30%  | 0,429%
  *         40%  | 0,667%
  *         50%  | 1,000%
  *         60%  | 1,500%
  *         70%  | 2,334%
  *         80%  | 4,000%
  *         90%  | 9,000%
  *         99%  |99,000%
  *        100%  |Infinity -> Impossible to provide 100% of resources
  **/
  function getPoolFee(uint256 amount) public view returns (uint256)  {
      /*
      * Calculates locked balance and checks it against total pool balance
      * Utilization of 100% is not allowed so locked balance must be less than pool balance
      */
      uint256 totalBalance = _token.balanceOf(address(this));
      uint256 lockedBalance = _lockedBalance + amount;
      require(lockedBalance < totalBalance, "Pool cannot have locked balance greater than or equal to total balance.");
      
      /*
      * Calculates unlocked balance as the difference between locked balance and pool balance
      */
      uint256 unlockedBalance = totalBalance - lockedBalance;

      /*
      * Calculates liquidity fee as
      *   Liquidity Fee(%) = (Unlocked Balance ÷ Locked Balance) ÷ 100
      */
      return lockedBalance.div(unlockedBalance).div(1e20);
  }

  /**
  * @dev Function used by liquidity providers to provide resources to the pool.
  * Liquidity provider transfers amount of ERC20 token and receives new share tokens minted by the pool. 
  **/
  function deposit(address from, uint256 amount) external nonReentrant {
    
    /*
    * Calculates PST tokens to be minted
    */
    uint256 totalBalance = _token.balanceOf(address(this));
    uint256 shareBalance = _poolShareToken.totalSupply() + _poolWithdrawToken.totalSupply();
    uint256 shareAmount = amount;
    if (totalBalance != 0) {
      shareAmount = amount.mul(shareBalance.div(totalBalance));
    }

    /*
    * Transfers amount from liquidity provider to the pool contract using approve/transferFrom
    */
    _token.transferFrom(from, address(this), amount);

    /*
    * Mint share tokens to liquidity provider
    */
    _poolShareToken.mint(from, shareAmount);

    emit LiquidityDeposit(from, amount, shareAmount, _token.balanceOf(address(this)));

  }

  /**
  * @dev Function used by liquidity providers to withdraw resources from the pool.
  *
  * Liquidity provider receives proportional unlocked amount of tokens + postdate withdraw tokens. 
  * Pool burns all share tokens.
  **/
  function withdraw(address to, uint256 amount) external nonReentrant {
      
      /*
      * Remaining amount gets recorded for transfer on future liquidation of options
      */
      _updateLockedBalance(0);
      uint256 remainingAmount = amount.mul(1e18 - (_token.balanceOf(address(this)) - _lockedBalance).div(_token.balanceOf(address(this))));
      /*
      * Transfers amount to liquidity provider
      */
      _transferWithdraw(to, _poolShareToken, amount, _token.balanceOf(address(this)) - _lockedBalance);

      /*
      * Remaining amount gets recorded for transfer on future liquidation of options
      */
      if ( remainingAmount > 0 ){
        _poolWithdrawToken.mint(to, remainingAmount);
        _postdatedWithdrawAllowances[to] = block.timestamp + 15 days; // Gets reset with each withdraw from LP address 
      }

      emit LiquidityWithdrawn(to, amount, remainingAmount, _token.balanceOf(address(this)));   
  }
  /**
  * @dev Function used by liquidity providers to postdate withdraw resources from the pool.
  *
  * Liquidity provider receives available amount of token. 
  **/
  function postdatedWithdraw(address to, uint256 amount) external nonReentrant {

      /* 
      * Checks date is after postdated defined for to address
      */
      require(_postdatedWithdrawAllowances[to] < block.timestamp, "Cannot withdraw postdated share before date.");

      /*
      * Transfers amount to liquidity provider
      */
      _updateLockedBalance(0);
      _transferWithdraw(to, _poolWithdrawToken, amount, _token.balanceOf(address(this)));

      /*
      * Remove LP from withdraw allowances
      */ 
      if (_poolWithdrawToken.balanceOf(to) == 0){
        delete _postdatedWithdrawAllowances[to];
      }

      emit LiquidityPostdatedWithdrawn(to, amount, _token.balanceOf(address(this)));   
  }

  function _transferWithdraw(address to, OptFiPoolToken pool, uint256 amount, uint256 balance) private {
      /*
      * Calculates share and burns pool tokens
      */
      uint256 share = pool.balanceOf(to).div(_poolShareToken.totalSupply() + _poolWithdrawToken.totalSupply());
      pool.burn(to, amount);
      
      /*
      * Calculates unlocked balance and verifies there is any to transfer
      */
      uint256 totalBalance = _token.balanceOf(address(this));
      uint256 unlockedBalance = totalBalance - _lockedBalance;
      require(unlockedBalance > 0, "There is no available funds to fulfill this request at the moment.");

      /*
      * Transfers from the pool to the liquidity provider its share of the balance
      */
      uint256 amountToTransfer = balance.mul(share);
      require(amountToTransfer <= unlockedBalance, "There is no available funds to fulfill this request at the moment.");
      _token.transfer(to, amountToTransfer);
  } 

  /**
  * @dev Function used by OptFi to send premium to the pool.
  *
  * The premium is in the same token the pool uses as collateral.
  *
  * Upon receiving the premium the pool will lock the collateral for the operation.
  *
  **/
  function receivePremium(address from, uint256 amount, uint256 collateralAmount, uint256 expiration, uint256 optionPrice, address protocolAddress, uint256 fee, uint256 maxPremiumPayment) external nonReentrant {
    require(_owner == msg.sender, "Ownable: caller is not the owner");

    /*
    * Calculate option premium and check against maximum premium
    */
    uint256 poolFee = getPoolFee(collateralAmount);   
    uint256 optionPremium = optionPrice.mul(1e18 + poolFee).mul(amount);
    require(optionPremium.mul(1e18 + fee) <= maxPremiumPayment,"Insufficient premium payment");
    
    /*
    * Transfers amount from options buyer to the pool contract using approve/transferFrom
    * Collect fees for the pool and protocol
    */
    uint256 totalFee = optionPremium.mul(fee);
    uint256 protocolFee = totalFee.mul(3e17);
    _token.transferFrom(from, protocolAddress, protocolFee);
    _token.transferFrom(from, address(this), optionPremium + totalFee - protocolFee);

    /*
    * Locks collateral
    */
    _lockBalance(collateralAmount, expiration);
    
    emit FeeCollected(from, totalFee);
    emit PremiumReceived(from, optionPremium, optionPrice, amount);
  }

  /**
  * @dev Function used by OptFi to pay premium to the options seller.
  *
  * The premium is in the same token the pool uses as collateral.
  *
  * Upon receiving the premium the pool will unlock the collateral for the operation.
  *
  **/
  function payPremium(address to, uint256 amount, uint256 collateralAmount, uint256 expiration, uint256 optionPrice, address protocolAddress, uint256 fee, uint256 minPremiumPayment) external nonReentrant {  
    require(_owner == msg.sender, "Ownable: caller is not the owner");

    /*
    * Calculate option premium and check agains maximum premium
    */
    uint256 optionPremium = optionPrice.mul(amount);
    uint256 totalFee = optionPremium.mul(fee);
    require(optionPremium - totalFee >= minPremiumPayment, "Insufficient premium payment");
    
    /*
    * Transfers amount from options buyer to the pool contract using approve/transferFrom
    * Collect fees for the pool and protocol
    */
    uint256 protocolFee = totalFee.mul(1e17);
    _token.transfer(protocolAddress, protocolFee);
    _token.transfer(to, optionPremium - totalFee + protocolFee);
    
    /*
    * Unlocks collateral
    */
    _unlockBalance(collateralAmount, expiration);
    
    emit FeeCollected(to, totalFee);
    emit PremiumPaid(to, optionPremium, optionPrice, amount);
  }

  /**
  * @dev Function used by the pool to lock collaterals.
  **/
  function _lockBalance(uint256 amount, uint256 expiration) private {
    /*
    * Unlocks collateral of expired options and returns the index + 1 for modification
    */
    uint256 indexToModify = _updateLockedBalance(expiration);

    /*
    * Verifies locked balance does not exceed pool total balance while updating total locked balance
    */
    uint256 totalBalance = _token.balanceOf(address(this));
    _lockedBalance += amount;
    require(totalBalance >= _lockedBalance, "Pool cannot have locked balance greater than total balance.");
    
    /*
    * Updates locked balance by expiration
    */
    if (indexToModify > 0){
      _lockedBalances[indexToModify - 1].balance += amount;
    }
    else{
      _lockedBalances.push(LockedBalance(expiration, amount));
    }

    emit LiquidityLocked(amount, expiration);

  }

  /**
  * @dev Function used by the pool to unlock collaterals.
  **/
  function _unlockBalance(uint256 amount, uint256 expiration) private {
    /*
    * Unlocks collateral of expired options and returns the index + 1 for modification
    * 
    * See _updateLockedBalance for detailed explanation
    */
    uint256 indexToModify = _updateLockedBalance(expiration);
    require (indexToModify > 0, "Could not find locked balance for this expiration.");

    /*
    * Updates total locked balance
    */
    require(_lockedBalance >= amount, "Pool cannot unlock amount greater than locked balance.");
    _lockedBalance -= amount;

    /*
    * Updates locked balance by expiration
    */
    _lockedBalances[indexToModify - 1].balance -= amount;
    if (_lockedBalances[indexToModify - 1].balance == 0){
      _lockedBalances[indexToModify - 1] = _lockedBalances[_lockedBalances.length-1];
      _lockedBalances.pop();
    }

    emit LiquidityUnlocked(amount, expiration);

  }

  /**
  * @dev Function used by the pool to remove expired locked balances.
  **/
  function _updateLockedBalance(uint256 expiration) private returns (uint256 indexToModify){
            
    for (uint256 i = 0; i < _lockedBalances.length; i++) {
      if (_lockedBalances[i].expiration < block.timestamp){
        _lockedBalance -= _lockedBalances[i].balance;
        emit LiquidityUnlocked(_lockedBalances[i].balance, _lockedBalances[i].expiration);
        if(_lockedBalances.length > 1){
          _lockedBalances[i] = _lockedBalances[_lockedBalances.length-1];
        }
        _lockedBalances.pop();
      }
      if(_lockedBalances.length > 0){
        if (_lockedBalances[i].expiration == expiration){
          indexToModify = i + 1;
        }
      }
    }
  }

  event PoolInitialized(IERC20Metadata _token, IERC20Metadata _poolShareToken, IERC20Metadata _poolWithdrawToken, address _owner);
  event LiquidityDeposit(address by, uint256 amount, uint256 shareAmount, uint256 totalBalance);
  event LiquidityWithdrawn(address by, uint256 requested, uint256 remaining, uint256 totalBalance);
  event LiquidityPostdatedWithdrawn(address by, uint256 sent, uint256 totalBalance);
  event LiquidityLocked(uint256 amount, uint256 expiration);
  event LiquidityUnlocked(uint256 amount, uint256 expiration);
  event PremiumReceived(address from, uint256 premium, uint256 optionPrice, uint256 amount);
  event PremiumPaid(address to, uint256 premium, uint256 optionPrice, uint256 amount);
  event FeeCollected(address from, uint256 fee);

  fallback() external {}

} 