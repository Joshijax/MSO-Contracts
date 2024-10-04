// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "../interfaces/IVault.sol";

library LiquidityHelpers {
    using SafeMath for uint;

    function mintPosition(
        address _positionManager,
        address _token0,
        address _token2,
        uint24 _poolFee,
        uint _token0Amount,
        uint _token2Amount,
        address _recipient
    )
        external
        returns (
            uint tokenId_,
            uint128 liquidity_,
            uint token2Amount_,
            uint token0Amount_
        )
    {   
        TransferHelper.safeApprove(_token0, _positionManager, _token0Amount);
        TransferHelper.safeApprove(_token2, _positionManager, _token2Amount);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: _token0,
                token1: _token2,
                fee: _poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: _token0Amount,
                amount1Desired: _token2Amount,
                amount0Min: _token0Amount.mul(90).div(100),
                amount1Min: _token2Amount.mul(90).div(100),
                recipient: _recipient,
                deadline: block.timestamp
            });

        (
            tokenId_,
            liquidity_,
            token0Amount_,
            token2Amount_
        ) = INonfungiblePositionManager(_positionManager).mint(params);

        TransferHelper.safeApprove(_token0, _positionManager, 0);
        TransferHelper.safeApprove(_token2, _positionManager, 0);
    }

    function increaseLiquidity(
        address _positionManager,
        uint _positionTokenId,
        address _token0,
        address _token2,
        uint _amount0,
        uint _amount2
    ) internal returns (uint liquidity_, uint amount0_, uint amount2_) {
        TransferHelper.safeApprove(
            _token0,
            _positionManager,
            _amount0
        );
        TransferHelper.safeApprove(
            _token2,
            address(_positionManager),
            _amount2
        );

        // Increase liquidity for the position
        (liquidity_, amount0_, amount2_) = INonfungiblePositionManager(_positionManager).increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: _positionTokenId,
                amount0Desired: _amount0,
                amount1Desired: _amount2,
                amount0Min: _amount0.mul(9).div(10),
                amount1Min: _amount2.mul(9).div(10),
                deadline: block.timestamp
            })
        );

        // Reset approvals to zero for security
        TransferHelper.safeApprove(_token0, _positionManager, 0);
        TransferHelper.safeApprove(_token2, _positionManager, 0);
    }

    function decreaseLiquidity(
        address _positionManager,
        uint256 _positionTokenId,
        uint128 _liquidity
    ) external returns (uint256 amount0_, uint256 amount2_) {
        (amount0_, amount2_) = INonfungiblePositionManager(_positionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: _positionTokenId,
                liquidity: _liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );
    }

    function swapExactInputSingle(
        address _swapRouter,
        address _tokenIn,
        address _tokenOut,
        uint _amountIn,
        uint24 _poolFee,
        address _recipient
    ) internal returns (uint amountOut_) {
        // Approve the swap
        TransferHelper.safeApprove(_tokenIn, _swapRouter, _amountIn);

        // Execute the swap and return the amount of tokenOut received
        amountOut_ = ISwapRouter(_swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: _poolFee,
                recipient: _recipient,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }


    function collectAllFees(address _positionManager, uint256 _tokenId) external returns (uint256 amount0_, uint256 amount2_) {
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0_, amount2_) = INonfungiblePositionManager(_positionManager).collect(params);
    }
}
