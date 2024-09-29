//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./MSOInvestorInterface.sol";
import "./SyntheticToken.sol";
import "./PositionInfoManager.sol";

interface IVault {
    function getAccessor() external view returns (address);
}

interface IComptroller {
    function buyShares(
        address _buyer,
        uint256 _investmentAmount,
        uint256 _minSharesQuantity
    ) external returns (uint256 sharesReceived);

    function redeemSharesForSpecificAssets(
        address _recipient,
        uint256 _sharesQuantity,
        address[] calldata _payoutAssets,
        uint256[] calldata _payoutAssetPercentages
    ) external returns (uint256[] memory payoutAmounts_);
}

struct MSOBalance {
    uint token1;
}

struct CollatedFees {
    uint token0;
    uint token2;
}

abstract contract MSOProcessingServerEntryPoint is MSOInvestorInterface {
    MSOBalance public balance;
    CollatedFees fees;
    address[] token1ToWithdraw = [token1];
    uint[] percentageToWithdraw = [100];
    PositionInfoManager positionInfoManager;

    function syncPrizeUp(uint _token1Amount) public onlyOracle {
        require(_token1Amount <= balance.token1);
        // Here ts > synth
        // withdraw t1 from treasury
        // redeem t0 from enzyme
        uint token0Amount = redeemInvestmentFromEnzyme(
            _token1Amount,
            token1ToWithdraw,
            percentageToWithdraw
        );
        // swap for token2
        uint token2Amount = swapExactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token2,
                fee: uniswapPoolFee,
                recipient: a(),
                deadline: block.timestamp,
                amountIn: token0Amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // burn it
        SyntheticToken(token2).burn(token2Amount);
    }

    function syncPrizeDown(uint _token2Amount) public onlyOracle {
        // Here ts < synth
        // Mint amount of token2 to sync price ===> get amount of token2 quantity
        SyntheticToken(token2).mint(a(), _token2Amount);
        // Swap to get token0 and get new ticks
        uint token0Amount = swapExactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token2,
                tokenOut: token0,
                fee: uniswapPoolFee,
                recipient: a(),
                deadline: block.timestamp,
                amountIn: _token2Amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Deposit to enzyme and get token1
        balance.token1 += buySharesFromEnzyme(token0Amount, 0);
    }

    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams memory _params
    ) internal {
        TransferHelper.safeApprove(
            token0,
            address(positionManager),
            _params.amount0Desired
        );
        TransferHelper.safeApprove(
            token2,
            address(positionManager),
            _params.amount1Desired
        );

        positionManager.increaseLiquidity(_params);

        TransferHelper.safeApprove(token0, address(positionManager), 0);
        TransferHelper.safeApprove(token2, address(positionManager), 0);
    }

    function swapExactInputSingle(
        ISwapRouter.ExactInputSingleParams memory _params
    ) internal returns (uint amountOut) {
        // require(msg.sender == a() || msg.sender == getOracle());
        TransferHelper.safeApprove(
            _params.tokenIn,
            address(swapRouter),
            _params.amountIn
        );
        require(_params.recipient == address(this));
        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(_params);
    }

    function buySharesFromEnzyme(
        uint _token0Amount,
        uint _minToken1Quantity
    ) internal returns (uint) {
        address comptrollerAddress = IVault(enzymeVault).getAccessor();
        require(
            IERC20(token0).approve(comptrollerAddress, _token0Amount),
            "Approval failed"
        );
        return
            IComptroller(comptrollerAddress).buyShares(
                a(),
                _token0Amount,
                _minToken1Quantity
            );
    }

    function redeemInvestmentFromEnzyme(
        uint256 _token1Amount,
        address[] memory _assetsToWithdraw,
        uint[] memory _percentages
    ) internal returns (uint) {
        address comptrollerAddress = IVault(token1).getAccessor();
        require(
            IERC20(token1).approve(comptrollerAddress, _token1Amount),
            "Approval failed"
        );

        return
            IComptroller(comptrollerAddress).redeemSharesForSpecificAssets(
                a(),
                _token1Amount,
                _assetsToWithdraw,
                _percentages
            )[0];
    }

    function collectFees() public onlyAfterLaunch {
        (uint token0Fees, uint token2Fees) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: a(),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        fees.token0 += token0Fees;
        fees.token2 += token2Fees;

        require(fees.token0 != 0 && investorBalance[msg.sender].token0 != 0);

        uint fee0 = ((investorBalance[msg.sender].token0 * fees.token0) /
            token0Balance);
        uint fee2 = ((investorBalance[msg.sender].token0 * fees.token2) /
            token0Balance);

        fees.token0 -= fee0;
        fees.token2 -= fee2;

        _runTransfer(token0, fee0, a(), msg.sender);
        _runTransfer(token2, fee2, a(), msg.sender);
    }

    function withdrawAfterLaunch(uint _tokenPercentage) public {
        uint token0Amount = investorBalance[msg.sender].token0;
        assert(token0Amount != 0);

        // get liquidity Info;
        (
            uint128 liquidity,
            uint128 token0Owed,
            uint128 token1Owed
        ) = positionInfoManager.getPosition(
                address(positionManager),
                positionTokenId
            );

        // Remove Liquidity
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionTokenId,
                liquidity: liquidity,
                amount0Min: (token0Owed / 100) * 90,
                amount1Min: (token1Owed / 100) * 90,
                deadline: block.timestamp
            })
        );

        uint withdrawableToken0Amount = ((IERC20(token0).balanceOf(a()) - fees.token0) *
            token0Amount) / token0Balance;
        uint withdrawableToken2Amount = ((IERC20(token2).balanceOf(a()) - fees.token2) *
            token0Amount) / token0Balance;

        _runTransfer(
            token0,
            (withdrawableToken0Amount * _tokenPercentage) / 100,
            a(),
            msg.sender
        );
        _runTransfer(
            token1,
            (investorBalance[msg.sender].token1 * _tokenPercentage) / 100,
            a(),
            msg.sender
        );
        _runTransfer(
            token2,
            (withdrawableToken2Amount * _tokenPercentage) / 100,
            a(),
            msg.sender
        );

        // return liquidity;
        increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: IERC20(token0).balanceOf(a()),
                amount1Desired: IERC20(token2).balanceOf(a()),
                amount0Min: (IERC20(token0).balanceOf(a()) * 90) / 100,
                amount1Min: (IERC20(token2).balanceOf(a()) * 90) / 100,
                deadline: block.timestamp
            })
        );
    }
}
