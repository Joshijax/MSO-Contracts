//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./SyntheticToken.sol";
import "./libraries/StructsAndEnums.sol";
import "./libraries/Events.sol";
import "./MSOInitializer.sol";
import './libraries/DecimalConversion.sol';

abstract contract MSO is Events, StructsAndEnums {
    address public vaultProxy;
    address public vaultOwner;
    address public tsAddress;
    address public usdcAddress;
    address public synthAddress;
    address public MSOInitializerAddress;

    using SafeMath for uint256;
    using DecimalConversion for uint256;

    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;

    Deposit public deposit;

    Cap public cap;
    Balance public balance;
    InLiquidity public liquidityBalance;
    MSOStage public msoStage;

    uint public minFactor;
    uint public maxFactor;
    uint public minTokenShares;
    uint public positionTokenId;

    mapping(address => Balance) staked;

    modifier onlyProcessingServer() {
        require(msg.sender == getProcessingServer(), "Not the owner");
        _;
    }

    modifier onlySelf() {
        require(msg.sender == address(this), "Must be called by self");
        _;
    }

    constructor(
        address _vaultProxy,
        address _vaultOwner,
        address _tsAddress,
        address _usdcAddress,
        address _positionManager,
        address _swapRouter,
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

        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
    }

    function stake(uint _tsAmount, uint _usdcAmount) public {
        require(msoStage == MSOStage.INIT, "MSO stage error");
        require(
            _tsAmount.mul(minFactor) <= _usdcAmount.from6to18dec() &&
                _tsAmount.mul(maxFactor) >= _usdcAmount.from6to18dec(),
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
        require(msoStage == MSOStage.CANCELED, "Too late");
        uint usdcBalance = staked[msg.sender].usdc;
        uint tsBalance = staked[msg.sender].ts;
        require(
            IERC20(usdcAddress).transferFrom(
                address(this),
                msg.sender,
                usdcBalance
            ),
            "USDC tranfer failed"
        );
        require(
            IERC20(tsAddress).transferFrom(
                address(this),
                msg.sender,
                tsBalance
            ),
            "USDC tranfer failed"
        );

        balance.usdc -= usdcBalance;
        balance.ts -= tsBalance;
    }

    function launchMSO(
        address _ProcessingServer,
        SyntheticTokenConfig memory _tokenConfig,
        INonfungiblePositionManager.MintParams memory _params,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        require(
            _ProcessingServer == getProcessingServer(),
            "Must be signed by processing server"
        );
        bytes32 hash = keccak256(abi.encode(_ProcessingServer, _tokenConfig, _params));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _ProcessingServer, "Invalid inputs");
        require(vaultOwner == msg.sender, "Only vault owner can launch mso");
        _launchMSO(_tokenConfig, _params);
    }

    function _launchMSO(
        SyntheticTokenConfig memory _tokenConfig,
        INonfungiblePositionManager.MintParams memory _params
    ) internal {
        require(msoStage == MSOStage.INIT, "MSO stage error");
        require(balance.usdc >= cap.soft, "Soft cap has not been reached");

        SyntheticToken token = new SyntheticToken(
            _tokenConfig.name,
            _tokenConfig.symbol
        );
        token.mint(address(this), _params.amount1Desired);

        //-------------------- Mint a position on uniswap --------------------//
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

        (uint tokenId, , uint synthAmount, uint usdcAmount) = positionManager
            .mint(_params);
        positionTokenId = tokenId;
        liquidityBalance.synth = synthAmount;
        liquidityBalance.usdc = usdcAmount;

        //The Liquidity pool contract address

        emit MSOLaunched(address(this), tsAddress, address(token), usdcAmount);
    }

    function cancelMSO() public {
        require(msg.sender == vaultOwner, "Only vault owner can cancel mso");
        require(msoStage == MSOStage.INIT, "Too late");
        msoStage = MSOStage.CANCELED;

        emit MSOCanceled(vaultProxy, tsAddress);
    }

    function reInitializeMSO() public {
        require(
            vaultOwner == msg.sender,
            "Only vault owner can initialize MSO"
        );
        msoStage = MSOStage.INIT;
        emit MSOInitialized(vaultOwner, vaultProxy);
    }

    function getProcessingServer() public view returns (address) {
        return MSOInitializer(MSOInitializerAddress).getOracleAddress();
    }
}
