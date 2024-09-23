//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./libraries/DecimalConversion.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

struct MSOConfig {
    uint lockPeriod;
    uint launchTimeCap;
    uint usdcSoftCap;
    uint minUsdcPerInvestment;
    uint minFactor;
    uint maxFactor;
    address enzymeVaultOwner;
    address tsAddress;
    address usdcAddress;
}

struct LaunchDetail {
    uint canWithdrawAt;
    Balance balance;
    address accessor;
    uint uniswapPositionTokenId;
}

enum MSOStage {
    INITIAL,
    LAUNCHED
}

struct Balance {
    uint usdc;
    uint ts;
}

contract MSOInvestorInterface is IERC721Receiver {
    using DecimalConversion for uint256;
    using SafeMath for uint256;

    MSOConfig config;
    MSOStage stage;
    LaunchDetail launchDetails;

    mapping(address => Balance) deposits;

    event Deposit(address depositor, uint tsAmount, uint usdcAmount);
    event Withdrawal(address widthrawer, uint tsAmount, uint usdcAmount);

    modifier onlyAccessor {
        assert(msg.sender == launchDetails.accessor);
        _;
    }

    function deposit(uint _tsAmount, uint _usdcAmount) public {
        require(
            _tsAmount.mul(config.minFactor) <= _usdcAmount.from6to18dec() &&
                _tsAmount.mul(config.maxFactor) >= _usdcAmount.from6to18dec(),
            "Not enough or too much USDC"
        );
        require(
            _tsAmount.from18to6dec() == _usdcAmount,
            "Token shares and USDC have to be the same amount"
        );
        require(
            config.minUsdcPerInvestment <=
                deposits[msg.sender].usdc.add(_usdcAmount),
            "USDC below the min investment"
        );

        _runTransfers(_tsAmount, _usdcAmount, msg.sender, a());

        deposits[msg.sender].usdc += _usdcAmount;
        deposits[msg.sender].ts += _tsAmount;

        emit Deposit(msg.sender, _tsAmount, _usdcAmount);
    }

    function widthraw(uint _pairAmount18Decimals) public {
        require(
            launchDetails.canWithdrawAt <= block.timestamp ||
                (config.launchTimeCap <= block.timestamp &&
                    stage == MSOStage.INITIAL),
            "Its a tad too early"
        );

        //do some stuff

        emit Withdrawal(
            msg.sender,
            _pairAmount18Decimals,
            _pairAmount18Decimals.from18to6dec()
        );
    }

    function runAssetTransfers(
        uint _tsAmount,
        uint _usdcAmount,
        address _from,
        address _to
    ) public onlyAccessor {
        _runTransfers(_tsAmount, _usdcAmount, _from, _to);
    }

    function runAssetTransfer(
        address _token,
        uint _amount,
        address _from,
        address _to
    ) public onlyAccessor {
        _runTransfer(_token, _amount, _from, _to);
    }

    //----------------------------Internal functions----------------------------//

    function _runTransfers(
        uint _tsAmount,
        uint _usdcAmount,
        address _from,
        address _to
    ) internal {
        require(
            IERC20(config.usdcAddress).transferFrom(_from, _to, _usdcAmount),
            "Failed to tranfer USDC"
        );
        require(
            IERC20(config.tsAddress).transferFrom(_from, _to, _tsAmount),
            "Failed to tranfer token shares"
        );
    }

    function _runTransfer(
        address _token,
        uint _amount,
        address _from,
        address _to
    ) internal {
        require(
            IERC20(_token).transferFrom(_from, _to, _amount),
            "Failed to tranfer tokens"
        );
    }

    function a() public view returns (address) {
        return address(this);
    }



    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        launchDetails.uniswapPositionTokenId = tokenId;
        return this.onERC721Received.selector;
    }
}
