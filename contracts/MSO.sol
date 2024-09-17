//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SyntheticToken.sol";
import "./libraries/StructsAndEnums.sol";
import "./libraries/Events.sol";

abstract contract MSO is Events, StructsAndEnums {
    address public vaultProxy;
    address public vaultOwner;
    address public tsAddress;
    address public usdcAddress;
    address public MSOServer;
    address public synthAddress;

    Cap public cap;
    Balance public balance;
    MSOStage public msoStage;

    uint public minFactor;
    uint public maxFactor;
    uint public minTokenShares;

    mapping(address => Balance) staked;

    constructor(
        address _vaultProxy,
        address _vaultOwner,
        address _tsAddress,
        address _usdcAddress,
        uint _minfactor,
        uint _maxFactor,
        uint _minTokenShares,
        uint _softcap,
        uint _hardcap
    ) {
        vaultOwner = _vaultOwner;
        vaultProxy = _vaultProxy;
        maxFactor = _maxFactor;
        minFactor = _minfactor;
        tsAddress = _tsAddress;
        usdcAddress = _usdcAddress;
        minTokenShares = _minTokenShares;
        cap.soft = _softcap;
        cap.hard = _hardcap;
    }

    function stake(uint _tsAmount, uint _usdcAmount) public {
        require(msoStage == MSOStage.INIT, "MSO stage error");
        require(
            _tsAmount * minFactor <= _usdcAmount &&
                _tsAmount * maxFactor >= _usdcAmount,
            "Not enough or too much USDC"
        );
        require(_tsAmount >= minTokenShares, "Not enough token shares");
        require(
            IERC20(usdcAddress).transferFrom(
                msg.sender,
                address(this),
                _usdcAmount
            ),
            "Failed to tranfer USDC"
        );
        require(
            IERC20(tsAddress).transferFrom(
                msg.sender,
                address(this),
                _tsAmount
            ),
            "Failed to tranfer token shares"
        );

        balance.ts += _tsAmount;
        balance.usdc += _usdcAmount;

        staked[msg.sender].usdc += _usdcAmount;
        staked[msg.sender].ts += _tsAmount;

        emit TokenSharesStaked(
            msg.sender,
            vaultProxy,
            tsAddress,
            _usdcAmount,
            _tsAmount
        );
    }

    function unstake() public {
        // require(msoStage == MSOStage.CANCELED, "Too late");
        uint usdcBalance = staked[msg.sender].usdc;
        uint tsBalance = staked[msg.sender].ts;
        require(
            IERC20(usdcAddress).transferFrom(address(this), msg.sender, usdcBalance),
            "USDC tranfer failed"
        );
        require(
            IERC20(tsAddress).transferFrom(address(this), msg.sender, tsBalance),
            "USDC tranfer failed"
        );

        balance.usdc -= usdcBalance;
        balance.ts -= tsBalance;


    }

    function launchMSO(
        address _MSOServer,
        bytes memory _data,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        // require(_MSOServer == MSOServer, "Must be called by MSO server EOA");
        bytes32 hash = keccak256(abi.encodePacked(_MSOServer, _data));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _MSOServer, "Invalid inputs");
        require(vaultOwner == msg.sender, "Only vault owner can launch mso");
        (bool success, ) = address(this).call(_data);
        require(success);
    }

    function _launchMSO(uint _synthTokenAmount, string memory _tokenName, string memory _tokenSymbol) public {
        require(msoStage == MSOStage.INIT, "MSO stage error");
        require(balance.usdc >= cap.soft, "Soft cap has not been reached");
        require(msg.sender == address(this), "Must be called by self");

        SyntheticToken token = new SyntheticToken(address(this), _tokenName, _tokenSymbol);
        token.mint(address(this), _synthTokenAmount);

        //-------------------- Mint a position on uniswap --------------------//

        emit MSOLaunched(vaultProxy, tsAddress, address(token));
    }

    function cancelMSO() public {
        require(msg.sender == vaultOwner, "Only vault owner can cancel mso");
        require(msoStage == MSOStage.INIT, "Too late");
        msoStage = MSOStage.CANCELED;

        emit MSOCanceled(vaultProxy, tsAddress);
    }

    function reInitializeMSO() public {
        require(vaultOwner == msg.sender, "Only vault owner can initialize MSO");
        msoStage = MSOStage.INIT;
        emit MSOInitialized(vaultOwner, vaultProxy);
    }

    
}
