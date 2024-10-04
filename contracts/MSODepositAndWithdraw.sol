// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./SyntheticToken.sol";
import "./MSOInitializer.sol";
import "./libraries/helpers.sol";
import "./libraries/EnzymeHelpers.sol";
import "./libraries/LiquidityHelpers.sol";
import "./MSOBase.sol";

contract MSODepositAndWithdraw is MSOBase {
    using SafeMath for uint;
    using SafeMath for uint128;


    function participate(uint _amount0) external {
        Helpers.runTransfers(
            token1,
            token0,
            Helpers.getToken1Amount(_amount0, token1, token0),
            _amount0,
            msg.sender,
            address(this)
        );

        (, uint amount0_, uint amount2_) = config.msoInitializer.getPosition(
            positionTokenId
        );

        uint amount2 = amount2_.mul(_amount0).div(amount0_);
        SyntheticToken(token2).mint(address(this), amount2);

        (, amount0_, amount2_) = LiquidityHelpers.increaseLiquidity(
            config.positionManager,
            positionTokenId,
            token0,
            token2,
            _amount0,
            amount2
        );

        if (amount2_ < amount2) {
            SyntheticToken(token2).burn(amount2.sub(amount2_));
        }

        if (amount0_ < _amount0) {
            Helpers.runTransfer(
                token0,
                _amount0.sub(amount0_),
                address(this),
                msg.sender
            );
        }

        deposits[msg.sender] = deposits[msg.sender].add(amount0_);
    }

    function withdraw(uint _amount0Percentage) external {
        uint totalVesting = deposits[msg.sender];
        require(totalVesting > 0);
        require(_amount0Percentage <= 100);


        (uint128 liquidity, ,) = config.msoInitializer.getPosition(
            positionTokenId
        );

        LiquidityHelpers.decreaseLiquidity(
            config.positionManager,
            positionTokenId,
            liquidity
        );

        uint total0 = ERC20(token0).balanceOf(address(this));
        uint total1 = ERC20(token1).balanceOf(address(this)).sub(balance1);

        
        uint return0 = totalVesting.mul(total0).div(balance0);
        uint return1 = Helpers.getToken1Amount(totalVesting, token1, token0).mul(total1).div(balance0);

        Helpers.runTransfers(
            token1,
            token0,
            return1.mul(_amount0Percentage).div(100),
            return0.mul(_amount0Percentage).div(100),
            address(this),
            msg.sender
        );


        //Emit an event

    }
}
