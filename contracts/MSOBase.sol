// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./SyntheticToken.sol";
import "./MSOInitializer.sol";
import "./libraries/helpers.sol";
import "./libraries/EnzymeHelpers.sol";
import "./libraries/LiquidityHelpers.sol";

abstract contract MSOBase is IERC721Receiver {
    struct Config {
        address positionManager;
        address swapRouter;
        address msoLauncher;
        address msoDepositAndWithdraw;
        address msoFeeCollector;
        address msoPriceSync;
        uint minInvestment;
        uint lockPeriod;
        uint investmentSoftCap;
        MSOInitializer msoInitializer;
    }

    struct AllTimeFee {
        uint fee0;
        uint fee2;
    }


    using SafeMath for uint;
    using SafeMath for uint128;

    address token0;
    address token1;
    address token2;

    uint decimals0;
    uint decimals1;

    Config config;
    uint24 poolFee;
    uint public positionTokenId;
    address[] token1ToWithdraw = [token1];
    uint[] percentageToWithdraw = [100];
    uint24 public uniswapPoolFee = 10000;

    bool readyToLaunch = false;
    bool isLaunched = false;

    uint balance0;
    uint balance1;
    uint fee0;
    uint fee2;
    AllTimeFee fees;

    mapping(address => uint) deposits;
    mapping(address => AllTimeFee) collatedFees;

    modifier onlyOracle{
        assert(msg.sender == config.msoInitializer.getOracleAddress());
        _;
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        positionTokenId = tokenId;

        return this.onERC721Received.selector;
    }
}
