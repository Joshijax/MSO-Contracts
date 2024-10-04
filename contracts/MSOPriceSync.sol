// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./MSOBase.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./SyntheticToken.sol";
import "./MSOInitializer.sol";
import "./libraries/helpers.sol";
import "./libraries/EnzymeHelpers.sol";
import "./libraries/LiquidityHelpers.sol";

contract MSOPriceSync is MSOBase {
    using SafeMath for uint;
    using SafeMath for uint128;
    function syncUp(uint _amount1) external {
        // Redeem token0 from Enzyme by withdrawing token1
        uint amount0 = EnzymeHelper.redeemInvestmentFromEnzyme(
            token1,
            _amount1,
            address(this),
            token1ToWithdraw,
            percentageToWithdraw
        );
        balance1 = balance1.sub(_amount1);
        // Swap token0 for token2 to adjust price
        uint amount2 = LiquidityHelpers.swapExactInputSingle(
            config.swapRouter,
            token0,
            token2,
            amount0,
            uniswapPoolFee,
            address(this)
        );
        // Burn token2 to adjust supply
        SyntheticToken(token2).burn(amount2);
    }

    function syncDown(uint _amount2) external {
        // Mint new token2 tokens to adjust price
        SyntheticToken(token2).mint(address(this), _amount2);
        // Swap token2 for token0 to adjust price
        uint amount0 = LiquidityHelpers.swapExactInputSingle(
            config.swapRouter,
            token2,
            token0,
            _amount2,
            uniswapPoolFee,
            address(this)
        );
        // Deposit token0 to Enzyme and receive token1 shares
        balance1 = balance1.add(
            EnzymeHelper.buySharesFromEnzyme(
                token0,
                token1,
                amount0,
                0,
                address(this)
            )
        );
    }
}
