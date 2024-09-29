//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./libraries/DecimalConversion.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./libraries/StructsAndEnums.sol";
import "./MSOInitializer.sol";
import "./SyntheticToken.sol";


abstract contract MSOInvestorInterface is StructsAndEnums, IERC721Receiver {
    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;

    using SafeMath for uint256;

    address token0; // enzyme vault investment token
    address token1; // enzyme vault token (TS)
    address token2; // Synthetic token 

    address enzymeVaultOwner;
    address enzymeVault;

    MSOStages stage = MSOStages.BEFORE;

    uint token0Decimals;
    uint token1Decimals;

    uint minToken0;
    uint lockPeriod;
    uint launchWindowExpirationPeriod = 30 days;
    uint launchWindowExpiresAt;
    uint token0Softcap;
    uint msoInitializer;

    uint24 uniswapPoolFee;
    
    uint token0Balance;
    uint token1Balance;

    uint positionTokenId;

    mapping (address => Balance) investorBalance;

    event Deposit(address investor, uint token0Amount, uint token1Amount);
    event Withdrawal(address investor, uint token0Amount);
    event Launched(uint token2Amount, uint token0Amount);

    modifier onlyOracle {
        require(msg.sender == getOracle());
        _;
    }

    modifier onlySelf {
        require(msg.sender == a());
        _;
    }

    modifier onlyAfterLaunch {
        require(stage == MSOStages.LAUNCHED, "MSO has not launched");
        _;
    }

    function deposit(uint _token0Amount) public {
        require(_token0Amount >= minToken0, "Token0 is less than threshold");
        uint token1Amount = getToken1Amount(_token0Amount);
        _runTransfers(token1Amount, _token0Amount, msg.sender, a());

        uint currentToken0Balance = token0Balance + _token0Amount;

        token0Balance+=_token0Amount;
        token1Balance+= token1Amount;

        if(token0Softcap <= currentToken0Balance) {
            stage = MSOStages.READY;
            launchWindowExpiresAt = block.timestamp + launchWindowExpirationPeriod;
        }

        investorBalance[msg.sender].token0 = _token0Amount;
        investorBalance[msg.sender].token1 = token1Amount;

        emit Deposit(msg.sender, _token0Amount, token1Amount);
    }

    function withdraw(uint _token0Amount) public {
        require(stage == MSOStages.BEFORE || stage == MSOStages.READY && block.timestamp >= launchWindowExpiresAt, "Can't withdraw funds at the moment");
        assert(investorBalance[msg.sender].token0 >= _token0Amount);

        uint token1Amount = getToken1Amount(_token0Amount);

        _runTransfers(token1Amount, _token0Amount, a(), msg.sender);
        investorBalance[msg.sender].token1 -= token1Amount;
        investorBalance[msg.sender].token0 -= _token0Amount;

        emit Withdrawal(msg.sender, _token0Amount);
    }

    function launch(
        address _oracle,
        LaunchParams memory _launchParams,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        require(stage == MSOStages.READY, "MSO is not yet ready for launch");
        require(
            _oracle == getOracle(),
            "Must be signed by oracle"
        );
        bytes32 hash = keccak256(abi.encode(_oracle, _launchParams));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _oracle, "Invalid inputs");
        require(enzymeVaultOwner == msg.sender, "Only vault owner can launch mso");
        _launch(_launchParams);
    }

    function _launch(LaunchParams memory _launchParams) internal {
        //Deploy token2 contract
        SyntheticToken token2Contract = new SyntheticToken(_launchParams.token2Name, _launchParams.token2Symbol);

        //mint the neccessary amount of token2 tokens;
        token2Contract.mint(a(), _launchParams.token2Amount);
        token2 = address(token2Contract);

        TransferHelper.safeApprove(
            token0,
            address(positionManager),
            _launchParams.liquidityParams.amount0Desired
        );
        TransferHelper.safeApprove(
            token2,
            address(positionManager),
            _launchParams.liquidityParams.amount1Desired
        );

        (uint tokenId, , uint token2Amount, uint token0Amount) = positionManager.mint(_launchParams.liquidityParams);
        positionTokenId = tokenId;

        stage = MSOStages.LAUNCHED;

        emit Launched(token2Amount, token0Amount);
    }
    

    function getOracle() public view returns(address) {
        return MSOInitializer(msoInitializer).getOracleAddress();
    }

    //----------------------------Internal functions----------------------------//


    function getToken1Amount(uint _token0Amount) public view returns(uint) {
        return (_token0Amount * 10 ** token1Decimals)/ 10 ** token0Decimals;
    }

    function _runTransfers(
        uint _token1Amount,
        uint _token0Amount,
        address _from,
        address _to
    ) internal {
        require(
            IERC20(token0).transferFrom(_from, _to, _token0Amount),
            "Failed to tranfer USDC"
        );
        require(
            IERC20(token1).transferFrom(_from, _to, _token1Amount),
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
        bytes memory __
    ) external override returns (bytes4) {
        positionTokenId = tokenId;
        return this.onERC721Received.selector;
    }
}
