// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./SyntheticToken.sol";
import "./libraries/LiquidityHelpers.sol";
import "./MSOInitializer.sol";
import "./MSOBase.sol";

contract MSOLauncher is MSOBase {
    using SafeMath for uint;
    using SafeMath for uint128;


    function launchMSO(
        uint _amount2,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external {
        SyntheticToken token2_ = new SyntheticToken(
            _tokenName,
            _tokenSymbol,
            address(this)
        );

        token2 = address(token2_);
        token2_.mint(address(this), _amount2);

        (uint tokenId, , , uint amount2) = LiquidityHelpers.mintPosition(
            config.positionManager,
            token0,
            token2,
            poolFee,
            balance0,
            _amount2,
            address(this)
        );

        positionTokenId = tokenId;

        if (amount2 < _amount2) {
            token2_.burn(_amount2.sub(amount2));
        }

        isLaunched = true;
    }
}