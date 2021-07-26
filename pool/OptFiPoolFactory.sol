// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


import "./OptFiPool.sol";

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title Implementation of the Pool Factory
 * @author s4p40-d3fi
 * @dev This contract implements a factory for liquidity pools backed by ERC20 tokens
 */

 contract OptFiPoolFactory is Ownable, ReentrancyGuard{

    OptFiPool private _poolImplementation;
    mapping(IERC20 => OptFiPool) private _pools;

    constructor()
    {
        _poolImplementation = new OptFiPool();
        _poolImplementation.initializeImplementation();
    }

    /**
     * @dev Gets existing pool contract for the parameters provided.
     * @param token The contract address of the ERC20 token this pool provides liquidity for
     * @return The pool contract
     */
    function getPool(IERC20Metadata token) external view returns (OptFiPool) {   
        return _pools[token];
    }

    /**
     * @dev Creates a new liquidity pool.
     * @param token The contract address of the ERC20 token this pool provides liquidity for
     * @return The pool contract
     */
    function createPool(IERC20Metadata token, address poolOwner) external onlyOwner nonReentrant returns (OptFiPool) {
        /*
        * Clones and initializes contract
        */
        require(address(_pools[token]) == address(0), "There is already a pool created for the token provided");
        _pools[token] = OptFiPool(Clones.clone(address(_poolImplementation)));
        
        OptFiPoolToken shareToken = _createShareToken(token.symbol());
        shareToken.transferOwnership(address(_pools[token]));
        
        OptFiPoolToken withdrawToken = _createWithdrawToken(token.symbol());
        withdrawToken.transferOwnership(address(_pools[token]));
        
        _pools[token].initialize(token, poolOwner, shareToken, withdrawToken);

        emit PoolCreated(_pools[token], shareToken, withdrawToken);

        return _pools[token];
    }

      /**
  * @dev Function used by the pool factory to create pool share tokens
  *
  * Pool share tokens are extended ERC20 contracts that implement tradeable flag allowing for transfer of the tokens
  * Share tokens are created as tradeable what means they can be transferred as any ERC20 token using transfer/transferFrom
  **/
  function _createShareToken(string memory tokenSymbol) private returns (OptFiPoolToken){
    return new OptFiPoolToken(string(abi.encodePacked('OptFI ', tokenSymbol, ' pool share')), string(abi.encodePacked("PST-",tokenSymbol)), true);
  }

  /**
  * @dev Function used by the pool factory to create pool withdraw tokens
  *
  * Pool withdraw tokens are extended ERC20 contracts that implement tradeable flag allowing for transfer of the tokens
  * Withdraw tokens are created as NOT tradeable what means they can NOT be transferred as any ERC20 token using transfer/transferFrom
  **/
  function _createWithdrawToken(string memory tokenSymbol) private returns (OptFiPoolToken){
    return new OptFiPoolToken(string(abi.encodePacked('OptFI ', tokenSymbol, ' pool withdraw')), string(abi.encodePacked("PWT-",tokenSymbol)), false);
  }

    /**
     * @dev Emitted when a pool contract is created.
     * @param pool The pool contract created.
     */
    event PoolCreated(OptFiPool pool, OptFiPoolToken shareToken, OptFiPoolToken withdrawToken);

    fallback() external {}

 }