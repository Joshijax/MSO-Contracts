//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

contract PositionInfoManager {
    struct PositionInfo {
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
    }

    function getPosition(
        address _manager,
        uint _positonTokenId
    )
        external
        view
        returns (uint128 liquidity, uint128 token0Amount, uint128 token1Amount)
    {
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(
                _manager
            );
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            liquidity,
            ,
            ,
            token0Amount,
            token1Amount
        ) = positionManager.positions(_positonTokenId);
    }
}
