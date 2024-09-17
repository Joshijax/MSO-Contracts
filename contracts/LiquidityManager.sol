// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/StructsAndEnums.sol";
import "./MSO.sol";

abstract contract LiquidityManager is MSO, IERC721Receiver {


    function _increaseLiquidity(
       INonfungiblePositionManager.IncreaseLiquidityParams memory _params
    ) internal {
        TransferHelper.safeApprove(
            usdcAddress,
            address(positionManager),
            _params.amount0Desired
        );
        TransferHelper.safeApprove(
            synthAddress,
            address(positionManager),
            _params.amount1Desired
        );

        positionManager.increaseLiquidity(_params);
    }


    function _decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams memory _params) internal returns(uint usdcAmount, uint synthAmount) {
        (usdcAmount, synthAmount) = positionManager.decreaseLiquidity(_params);
    }

    function _collectFees() internal returns(INonfungiblePositionManager.CollectParams memory _params) {
        positionManager.collect(_params);
    }

    function getPositonInfo()
        public
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        return positionManager.positions(positionTokenId);
    }

    function _swapExactInputSingle(ISwapRouter.ExactInputSingleParams memory _params) internal returns (uint256 amountOut) {
        TransferHelper.safeApprove(_params.tokenIn, address(swapRouter), _params.amountIn);
        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(_params);
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        positionTokenId = tokenId;
        return this.onERC721Received.selector;
    }
}
