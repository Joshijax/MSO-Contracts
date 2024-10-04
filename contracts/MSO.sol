// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "./MSOInitializer.sol";
import "./libraries/helpers.sol";
import "./MSOBase.sol";

contract MSO is MSOBase {
    using SafeMath for uint;
    using SafeMath for uint128;

    constructor(
        address _token0,
        address _token1,
        address _positionManager,
        address _swapRouter,
        address _msoLauncher,
        address _msoDepositAndWithdraw,
        address _msoFeeCollector,
        address _msoPriceSync,
        uint _minInvestment,
        uint _lockPeriod,
        uint _investmentSoftCap,
        address _msoInitializer
    ) {
        token0 = _token0;
        token1 = _token1;

        config = Config(
            _positionManager,
            _swapRouter,
            _msoLauncher,
            _msoDepositAndWithdraw,
            _msoFeeCollector,
            _msoPriceSync,
            _minInvestment,
            _lockPeriod,
            _investmentSoftCap,
            MSOInitializer(_msoInitializer)
        );

        decimals0 = ERC20(token0).decimals();
        decimals1 = ERC20(token1).decimals();
    }

    function depositInvestment(uint _token0Amount) external {
        uint deposit = deposits[msg.sender];
        require(config.minInvestment.add(deposit) <= _token0Amount);
        require(!isLaunched);
        Helpers.runTransfers(
            token1,
            token0,
            _token1From0(_token0Amount),
            _token0Amount,
            msg.sender,
            address(this)
        );

        balance0 = balance0.add(_token0Amount);
        deposits[msg.sender] = deposit.add(_token0Amount);

        if (balance0 >= config.investmentSoftCap) {
            readyToLaunch = true;
        }

        // Emit event;
    }

    function withdrawInvestment(uint _token0Amount) external {
        require(!readyToLaunch);
        uint deposit = deposits[msg.sender];
        assert(deposit >= _token0Amount);

        Helpers.runTransfers(
            token1,
            token0,
            _token1From0(_token0Amount),
            _token0Amount,
            address(this),
            msg.sender
        );

        balance0 = balance0.sub(_token0Amount);
        deposits[msg.sender] = deposit.sub(_token0Amount);

        // Emit event;
    }

    function LaunchMSO(
        address _oracle,
        uint _amount2,
        uint24 _poolFee,
        string memory _tokenName,
        string memory _tokenSymbol,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external {
        require(!isLaunched);
        require(readyToLaunch);
        require(_oracle == getOracle());

        // Verify signature
        bytes32 hash = keccak256(abi.encodePacked(_oracle, _amount2));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _oracle);
        require(Helpers.getVaultOwner(token1) == msg.sender);

        poolFee = _poolFee;

        (bool success, ) = config.msoLauncher.delegatecall(
            abi.encodeWithSignature(
                "launchMSO(uint256,string,string)",
                _amount2,
                _tokenName,
                _tokenSymbol
            )
        );

        require(success);
        // Emit event
    }

    function collectFees() external {
        (bool success, ) = config.msoFeeCollector.delegatecall(abi.encodeWithSignature("collectFees()"));
        require(success);
        // Emit an event here
    }

    function depositAfterLaunch(uint _maxAmount0) external {
        (bool success, ) = config.msoDepositAndWithdraw.delegatecall(abi.encodeWithSignature("participate(uint256)", _maxAmount0));
        require(success);
        // Emit an event here
    }

    function withdrawAfterLaunch(uint _amout0Percentage) external {
        (bool success, ) = config.msoDepositAndWithdraw.delegatecall(abi.encodeWithSignature("withdraw(uint256)", _amout0Percentage));
        require(success);
        // Emit an event here
    }

    function syncPrice(bool _syncUp, uint _tokenAmount) external {
        string memory signature = _syncUp ? "syncUp(uint256)" : "syncDown(uint256)";
        (bool success, ) = config.msoPriceSync.delegatecall(abi.encodeWithSignature(signature, _tokenAmount));
        require(success);
        // Emit an event here
    }

    function _token1From0(
        uint _token0Amount
    ) internal view returns (uint token1Amount_) {
        token1Amount_ = _token0Amount.mul(10 ** decimals1).div(10 ** decimals0);
    }

    /**
     * @notice Retrieves the address of the oracle responsible for signing the launch and other oracle-based operations.
     * @return The oracle's address.
     */
    function getOracle() public view returns (address) {
        return config.msoInitializer.getOracleAddress();
    }
}
