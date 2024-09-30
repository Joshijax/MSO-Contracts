// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./MSOInitializer.sol";
import "./SyntheticToken.sol";
import "./interfaces/IComptrollerLib.sol";
import "./interfaces/IVault.sol";
import "./libraries/helpers.sol";
import "./libraries/StructsAndEnums.sol";
import "./MSO.sol";

contract MSOInitStage is StructsAndEnums {
    using SafeMath for uint256;
    using SafeMath for uint128;


    ////////////////////////////
    //// Liquidity State  //////
    ////////////////////////////
    address public positionManager;
    address public swapRouter;

    ////////////////////////////
    //// Token State  //////////
    ////////////////////////////
    address public token0; // enzyme vault investment token
    address public token1; // enzyme vault token (TS)
    address public token2; // Synthetic token

    address public msoInitializer;
    address public msoAddress;

    ///////////////////////////
    //// Deposit State ////////
    ///////////////////////////
    MSOStages stage = MSOStages.BEFORE;
    uint public minToken0;
    uint public lockPeriod;
    uint public launchWindowExpirationPeriod = 30 days;
    uint public launchWindowExpiresAt;
    uint public token0Softcap;
    uint public token0Balance;
    uint public token1Balance;

    mapping(address => Balance) investorBalance;

    ///////////////////////////
    //// Events ///////////////
    ///////////////////////////
    event Deposit(address investor, uint token0Amount, uint token1Amount);
    event Withdrawal(address investor, uint token0Amount);
    event Launched(uint token2Amount, uint token0Amount);
    event TSClaim(uint token1Amount);

    //////////////////////////
    //// Modifiers ///////////
    //////////////////////////
    modifier onlyOracle() {
        require(msg.sender == getOracle());
        _;
    }
    modifier onlySelf() {
        require(msg.sender == a());
        _;
    }

    /**
     * @notice Initializes the MSOInvestorInterface contract with the provided parameters.
     * @param _token0 The address of the investment token (token0).
     * @param _token1 The address of the Enzyme vault token (token1).
     * @param _positionManager The address of the Uniswap v3 position manager contract.
     * @param _swapRouter The address of the Uniswap v3 swap router contract.
     * @param _minToken0 The minimum required amount of token0 for deposits.
     * @param _lockPeriod The duration for which deposits are locked before launch.
     * @param _token0Softcap The soft cap for token0 before the MSO can launch.
     */
    constructor(
        address _token0,
        address _token1,
        address _positionManager,
        address _swapRouter,
        uint _minToken0,
        uint _lockPeriod,
        uint _token0Softcap
    ) {
        require(IVault(_token1).isTrackedAsset(_token0));

        // Initialize state variables
        msoInitializer = msg.sender;
        token0 = _token0;
        token1 = _token1;

        positionManager = _positionManager;
        swapRouter = _swapRouter;

        minToken0 = _minToken0;
        lockPeriod = _lockPeriod;
        token0Softcap = _token0Softcap;
    }

    /**
     * @notice Deposits a specified amount of token0 into the contract.
     * @param _token0Amount The amount of token0 to deposit.
     */
    function deposit(uint _token0Amount) public {
        require(_token0Amount >= minToken0);
        uint token1Amount = getToken1Amount(_token0Amount);

        // Transfer token0 and token1 from the investor to the contract
        Helpers.runTransfers(
            token1,
            token0,
            token1Amount,
            _token0Amount,
            msg.sender,
            a()
        );

        uint currentToken0Balance = token0Balance.add(_token0Amount);

        // Update contract balances
        token0Balance = token0Balance.add(_token0Amount);
        token1Balance = token1Balance.add(token1Amount);

        // Check if the soft cap has been reached
        if (token0Softcap <= currentToken0Balance) {
            stage = MSOStages.READY;
            launchWindowExpiresAt = block.timestamp.add(
                launchWindowExpirationPeriod
            );
        }

        // Record investor's balance
        investorBalance[msg.sender].token0 = _token0Amount;
        investorBalance[msg.sender].token1 = token1Amount;

        emit Deposit(msg.sender, _token0Amount, token1Amount);
    }

    /**
     * @notice Withdraws a specified amount of token0 from the contract.
     * @param _token0Amount The amount of token0 to withdraw.
     */
    function withdraw(uint _token0Amount) public {
        // Ensure withdrawals can be made based on the stage and timing
        require(
            stage == MSOStages.BEFORE ||
                (stage == MSOStages.READY &&
                    block.timestamp >= launchWindowExpiresAt)
        );
        assert(investorBalance[msg.sender].token0 >= _token0Amount);

        uint token1Amount = getToken1Amount(_token0Amount);

        // Transfer token0 and token1 back to the investor
        Helpers.runTransfers(
            token1,
            token0,
            token1Amount,
            _token0Amount,
            a(),
            msg.sender
        );

        // Update investor's balance
        investorBalance[msg.sender].token1 = investorBalance[msg.sender]
            .token1
            .sub(token1Amount);
        investorBalance[msg.sender].token0 = investorBalance[msg.sender]
            .token0
            .sub(_token0Amount);

        emit Withdrawal(msg.sender, _token0Amount);
    }

    /**
     * @notice Launches the MSO, deploying the synthetic token and creating a liquidity position on Uniswap.
     * @param _oracle The oracle address responsible for signing the launch.
     * @param _launchParams The parameters required for the launch.
     * @param _r The 'r' component of the signature.
     * @param _s The 's' component of the signature.
     * @param _v The 'v' component of the signature.
     */

    function launch(
        address _oracle,
        LaunchParams memory _launchParams,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) external {
        require(stage == MSOStages.READY);
        require(_oracle == getOracle());

        // Verify signature
        bytes32 hash = keccak256(abi.encode(_oracle, _launchParams));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _oracle);
        require(Helpers.getVaultOwner(token1) == msg.sender);

        // Internal function to perform the launch logic
        MSO mso = new MSO(
            token0,
            token1,
            positionManager,
            swapRouter,
            minToken0,
            _launchParams
        );

        msoAddress = address(mso);

        stage = MSOStages.LAUNCHED;

        Helpers.runTransfers(token1, token0, token1Balance, token0Balance, a(), msoAddress);
    }

    /**
     * @notice Retrieves the address of the oracle responsible for signing the launch and other oracle-based operations.
     * @return The oracle's address.
     */
    function getOracle() public view returns (address) {
        return MSOInitializer(msoInitializer).getOracleAddress();
    }

    /**
     * @notice Gets the corresponding token1 amount based on a specified token0 amount.
     * @param _token0Amount The amount of token0.
     * @return The corresponding amount of token1.
     */
    function getToken1Amount(uint _token0Amount) internal view returns (uint) {
        return
            _token0Amount.mul(10 ** ERC20(token1).decimals()).div(
                10 ** ERC20(token0).decimals()
            );
    }

    function getInvestmentBalance(address _investor) external view returns(Balance memory) {
        return investorBalance[_investor];
    }

    /**
     * @notice Returns the contract's address.
     * @return The address of the contract.
     */
    function a() public view returns (address) {
        return address(this);
    }
}
