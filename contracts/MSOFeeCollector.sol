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

contract MSOFeeCollector is MSOBase {
    using SafeMath for uint;
    using SafeMath for uint128;

    function collectFees() external {
        uint totalVesting = deposits[msg.sender];
        AllTimeFee storage f = collatedFees[msg.sender];
        require(totalVesting > 0);
        (uint amount0, uint amount2) = LiquidityHelpers.collectAllFees(
            config.positionManager,
            positionTokenId
        );

        fee0 = fee0.add(amount0);
        fee2 = fee2.add(amount2);

        fees.fee0 = fees.fee0.add(amount0);
        fees.fee2 = fees.fee2.add(amount2);

        uint return0 = totalVesting.mul(fees.fee0).div(balance0);
        uint return2 = totalVesting.mul(fees.fee2).div(balance0);

        uint remnant0 = return0.sub(f.fee0);
        uint remnant2 = return2.sub(f.fee2);

        fee0 = fee0.sub(remnant0);
        fee2 = fee2.sub(remnant2);

        f.fee0 = return0;
        f.fee2 = return2;

        Helpers.runTransfer(token0, remnant0, address(this), msg.sender);
        Helpers.runTransfer(token2, remnant2, address(this), msg.sender);

        // Emit and event
    }
}
