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
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./PositionInfoManager.sol";
import "./libraries/StructsAndEnums.sol";
import "./MSOInitializer.sol";
import "./SyntheticToken.sol";

interface IVault {
    function getAccessor() external view returns (address);

    function getOwner() external view returns (address);

    function isTrackedAsset(address _asset) external view returns (bool);
}

interface IComptrollerLib {
    function buyShares(
        address _buyer,
        uint256 _investmentAmount,
        uint256 _minSharesQuantity
    ) external returns (uint256 sharesReceived);

    function redeemSharesForSpecificAssets(
        address _recipient,
        uint256 _sharesQuantity,
        address[] calldata _payoutAssets,
        uint256[] calldata _payoutAssetPercentages
    ) external returns (uint256[] memory payoutAmounts_);
}

abstract contract MSO is StructsAndEnums, IERC721Receiver {
    using SafeMath for uint256;
    using SafeMath for uint128;

    ////////////////////////////
    /// Liquidity State  ///////
    ////////////////////////////
    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;
    MSOBalance public balance;
    CollatedFees fees;
    address[] token1ToWithdraw = [token1];
    uint[] percentageToWithdraw = [100];
    PositionInfoManager positionInfoManager;
    uint24 uniswapPoolFee;
    uint positionTokenId;

    ////////////////////////////
    //// Token State  //////////
    ////////////////////////////
    address token0; // enzyme vault investment token
    address token1; // enzyme vault token (TS)
    address token2; // Synthetic token

    address msoInitializer;

    ///////////////////////////
    //// Deposit State ////////
    ///////////////////////////
    MSOStages stage = MSOStages.BEFORE;
    uint minToken0;
    uint lockPeriod;
    uint launchWindowExpirationPeriod = 30 days;
    uint launchWindowExpiresAt;
    uint token0Softcap;
    uint token0Balance;
    uint token1Balance;

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
    modifier onlyAfterLaunch() {
        require(stage == MSOStages.LAUNCHED, "MSO has not launched");
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
        require(
            IVault(_token1).isTrackedAsset(_token0),
            "Asset not tracked by vault"
        );

        // Initialize state variables
        msoInitializer = msg.sender;
        token0 = _token0;
        token1 = _token1;

        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);

        minToken0 = _minToken0;
        lockPeriod = _lockPeriod;
        token0Softcap = _token0Softcap;
    }

    /**
     * @notice Deposits a specified amount of token0 into the contract.
     * @param _token0Amount The amount of token0 to deposit.
     */
    function deposit(uint _token0Amount) public {
        require(_token0Amount >= minToken0, "Token0 is less than threshold");
        uint token1Amount = getToken1Amount(_token0Amount);

        // Transfer token0 and token1 from the investor to the contract
        _runTransfers(token1Amount, _token0Amount, msg.sender, a());

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
                    block.timestamp >= launchWindowExpiresAt),
            "Can't withdraw funds at the moment"
        );
        assert(investorBalance[msg.sender].token0 >= _token0Amount);

        uint token1Amount = getToken1Amount(_token0Amount);

        // Transfer token0 and token1 back to the investor
        _runTransfers(token1Amount, _token0Amount, a(), msg.sender);

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
        require(stage == MSOStages.READY, "MSO is not yet ready for launch");
        require(_oracle == getOracle(), "Must be signed by oracle");

        // Verify signature
        bytes32 hash = keccak256(abi.encode(_oracle, _launchParams));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == _oracle, "Invalid inputs");
        require(
            getVaultOwner() == msg.sender,
            "Only vault owner can launch MSO"
        );

        // Internal function to perform the launch logic
        _launch(_launchParams);
    }

    /**
     * @notice Collects fees accrued from the Uniswap liquidity position and distributes them proportionally to investors.
     */
    function collectFees() external onlyAfterLaunch {
        // Collect fees from Uniswap position
        (uint token0Fees, uint token2Fees) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: positionTokenId,
                recipient: a(),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        fees.token0 = fees.token0.add(token0Fees);
        fees.token2 = fees.token2.add(token2Fees);

        require(fees.token0 != 0 && investorBalance[msg.sender].token0 != 0);

        // Calculate fees owed to the caller based on their share of token0
        uint fee0 = (
            investorBalance[msg.sender].token0.mul(fees.token0).div(
                token0Balance
            )
        );
        uint fee2 = (
            investorBalance[msg.sender].token0.mul(fees.token2).div(
                token0Balance
            )
        );

        // Deduct collected fees
        fees.token0 = fees.token0.sub(fee0);
        fees.token2 = fees.token0.sub(fee2);

        // Transfer fees to the caller
        _runTransfer(token0, fee0, a(), msg.sender);
        _runTransfer(token2, fee2, a(), msg.sender);
    }

    function depositAfterLaunch(uint _maxToken0Amount) external {
        (, uint token0Owed, uint token2Owed) = positionInfoManager.getPosition(
            address(positionManager),
            positionTokenId
        );

        uint maxToken2Amount = token2Owed.mul(_maxToken0Amount).div(token0Owed);

        _runTransfers(
            getToken1Amount(_maxToken0Amount),
            _maxToken0Amount,
            msg.sender,
            a()
        );

        (uint amount0, uint amount2) = increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: _maxToken0Amount,
                amount1Desired: maxToken2Amount,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            })
        );

        if (_maxToken0Amount > amount0) {
            _runTransfers(
                getToken1Amount(_maxToken0Amount.sub(amount0)),
                _maxToken0Amount.sub(amount0),
                a(),
                msg.sender
            );
        }

        if (maxToken2Amount > amount2) {
            SyntheticToken(token2).burn(maxToken2Amount.sub(amount2));
        }

        Deposit(msg.sender, amount0, amount2);
    }

    /**
     * @notice Withdraws a portion of the user's token0, token1, and token2 after the MSO has been launched.
     * @param _tokenPercentage The percentage of the tokens to withdraw.
     */
    function withdrawAfterLaunch(uint _tokenPercentage) external {
        uint token0Amount = investorBalance[msg.sender].token0;
        assert(token0Amount != 0);

        // Get liquidity info for the position
        (
            uint128 liquidity,
            uint128 token0Owed,
            uint128 token1Owed
        ) = positionInfoManager.getPosition(
                address(positionManager),
                positionTokenId
            );

        // Remove Liquidity from Uniswap
        positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: positionTokenId,
                liquidity: liquidity,
                amount0Min: token0Owed.mul(90).div(100),
                amount1Min: token1Owed.mul(90).div(100),
                deadline: block.timestamp
            })
        );

        uint withdrawableToken0Amount = IERC20(token0)
            .balanceOf(a())
            .sub(fees.token0)
            .mul(token0Amount)
            .div(token0Balance);
        uint withdrawableToken2Amount = IERC20(token2)
            .balanceOf(a())
            .sub(fees.token2)
            .mul(token0Amount)
            .div(token0Balance);

        // Transfer withdrawable tokens to the investor
        _runTransfer(
            token0,
            withdrawableToken0Amount.mul(_tokenPercentage).div(100),
            a(),
            msg.sender
        );
        _runTransfer(
            token1,
            investorBalance[msg.sender].token1.mul(_tokenPercentage).div(100),
            a(),
            msg.sender
        );
        _runTransfer(
            token2,
            withdrawableToken2Amount.mul(_tokenPercentage).div(100),
            a(),
            msg.sender
        );

        // Re-add remaining liquidity to Uniswap
        increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: positionTokenId,
                amount0Desired: IERC20(token0).balanceOf(a()),
                amount1Desired: IERC20(token2).balanceOf(a()),
                amount0Min: IERC20(token0).balanceOf(a()).mul(90).div(100),
                amount1Min: IERC20(token2).balanceOf(a()).mul(90).div(100),
                deadline: block.timestamp
            })
        );

        emit Withdrawal(
            msg.sender,
            (withdrawableToken0Amount * _tokenPercentage) / 100
        );
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
            _token0Amount.mul(10 ** ERC20(token1).decimals()).div(10 ** ERC20(token0).decimals());
    }

    /**
     * @notice Handles the receipt of an ERC721 token, primarily used for handling the Uniswap position NFT.
     * @param tokenId The ID of the ERC721 token being received.
     * @return The selector confirming receipt of the ERC721 token.
     */
    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes memory
    ) external override returns (bytes4) {
        // Store the position token ID
        positionTokenId = tokenId;
        return this.onERC721Received.selector;
    }

    /**
     * @notice Launches the MSO by deploying the synthetic token and creating a liquidity position on Uniswap.
     * @param _launchParams The parameters required for the launch.
     */
    function _launch(LaunchParams memory _launchParams) internal {
        // Deploy synthetic token (token2)
        SyntheticToken token2Contract = new SyntheticToken(
            _launchParams.token2Name,
            _launchParams.token2Symbol
        );

        // Mint the necessary amount of token2
        token2Contract.mint(a(), _launchParams.token2Amount);
        token2 = address(token2Contract);

        uniswapPoolFee = _launchParams.poolFee;

        // Approve token0 and token2 to be used by the position manager
        TransferHelper.safeApprove(
            token0,
            address(positionManager),
            token0Balance
        );
        TransferHelper.safeApprove(
            token2,
            address(positionManager),
            _launchParams.token2Amount
        );

        // Mint a new liquidity position on Uniswap v3
        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token2,
                fee: uniswapPoolFee,
                tickLower: _launchParams.tickLower,
                tickUpper: _launchParams.tickUpper,
                amount0Desired: token0Balance,
                amount1Desired: _launchParams.token2Amount,
                amount0Min: token0Balance.mul(90).div(100),
                amount1Min: _launchParams.token2Amount.mul(90).div(100),
                recipient: address(this),
                deadline: block.timestamp
            });

        (uint tokenId, , uint token2Amount, uint token0Amount) = positionManager
            .mint(params);
        positionTokenId = tokenId;

        if (token2Amount < _launchParams.token2Amount) {
            token2Contract.burn((_launchParams.token2Amount.sub(token2Amount)));
        }

        stage = MSOStages.LAUNCHED;

        emit Launched(token2Amount, token0Amount);
    }

    /**
     * @notice Synchronizes the prize by adjusting the amount of token1 in the contract.
     * @param _token1Amount The amount of token1 to adjust.
     */
    function syncPrizeUp(uint _token1Amount) external onlyOracle {
        require(_token1Amount <= balance.token1, "Insufficient balance");

        // Redeem token0 from Enzyme by withdrawing token1
        uint token0Amount = redeemInvestmentFromEnzyme(
            _token1Amount,
            token1ToWithdraw,
            percentageToWithdraw
        );

        // Swap token0 for token2 to adjust price
        uint token2Amount = swapExactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token2,
                fee: uniswapPoolFee,
                recipient: a(),
                deadline: block.timestamp,
                amountIn: token0Amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Burn token2 to adjust supply
        SyntheticToken(token2).burn(token2Amount);
    }

    /**
     * @notice Synchronizes the prize by adjusting the amount of token2 in the contract.
     * @param _token2Amount The amount of token2 to adjust.
     */
    function syncPrizeDown(uint _token2Amount) external onlyOracle {
        // Mint new token2 tokens to adjust price
        SyntheticToken(token2).mint(a(), _token2Amount);

        // Swap token2 for token0 to adjust price
        uint token0Amount = swapExactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: token2,
                tokenOut: token0,
                fee: uniswapPoolFee,
                recipient: a(),
                deadline: block.timestamp,
                amountIn: _token2Amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        // Deposit token0 to Enzyme and receive token1 shares
        balance.token1 = balance.token1.add(buySharesFromEnzyme(token0Amount, 0));
    }

    /**
     * @notice Increases liquidity for the Uniswap position.
     * @param _params The parameters for increasing liquidity.
     */
    function increaseLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams memory _params
    ) internal returns (uint amount0, uint amount2) {
        TransferHelper.safeApprove(
            token0,
            address(positionManager),
            _params.amount0Desired
        );
        TransferHelper.safeApprove(
            token2,
            address(positionManager),
            _params.amount1Desired
        );

        // Increase liquidity for the position
        (, amount0, amount2) = positionManager.increaseLiquidity(_params);

        // Reset approvals to zero for security
        TransferHelper.safeApprove(token0, address(positionManager), 0);
        TransferHelper.safeApprove(token2, address(positionManager), 0);
    }

    /**
     * @notice Swaps a specified amount of an input token for an output token using Uniswap v3.
     * @param _params The parameters for the exact input single swap.
     * @return amountOut The amount of output tokens received from the swap.
     */
    function swapExactInputSingle(
        ISwapRouter.ExactInputSingleParams memory _params
    ) internal returns (uint amountOut) {
        // Approve the swap
        TransferHelper.safeApprove(
            _params.tokenIn,
            address(swapRouter),
            _params.amountIn
        );
        require(_params.recipient == address(this));

        // Execute the swap and return the amount of tokenOut received
        amountOut = swapRouter.exactInputSingle(_params);
    }

    /**
     * @notice Buys shares from the Enzyme vault with a specified amount of token0.
     * @param _token0Amount The amount of token0 to invest.
     * @param _minToken1Quantity The minimum quantity of token1 to receive.
     * @return The number of shares bought.
     */
    function buySharesFromEnzyme(
        uint _token0Amount,
        uint _minToken1Quantity
    ) internal returns (uint) {
        address comptrollerAddress = IVault(token1).getAccessor();
        require(
            IERC20(token0).approve(comptrollerAddress, _token0Amount),
            "Approval failed"
        );

        // Buy shares from the Enzyme vault
        return
            IComptrollerLib(comptrollerAddress).buyShares(
                a(),
                _token0Amount,
                _minToken1Quantity
            );
    }

    /**
     * @notice Redeems shares for specific assets from the Enzyme vault.
     * @param _token1Amount The number of shares to redeem.
     * @param _assetsToWithdraw The assets to withdraw from the vault.
     * @param _percentages The percentages of each asset to withdraw.
     * @return The amount of token0 received from redemption.
     */
    function redeemInvestmentFromEnzyme(
        uint256 _token1Amount,
        address[] memory _assetsToWithdraw,
        uint[] memory _percentages
    ) internal returns (uint) {
        address comptrollerAddress = IVault(token1).getAccessor();
        require(
            IERC20(token1).approve(comptrollerAddress, _token1Amount),
            "Approval failed"
        );

        // Redeem specific assets from Enzyme based on shares
        return
            IComptrollerLib(comptrollerAddress).redeemSharesForSpecificAssets(
                a(),
                _token1Amount,
                _assetsToWithdraw,
                _percentages
            )[0];
    }

    /**
     * @notice Retrieves the owner of the Enzyme vault.
     * @return The vault owner's address.
     */
    function getVaultOwner() internal view returns (address) {
        return IVault(token1).getOwner();
    }

    /**
     * @notice Transfers specified amounts of token0 and token1 between addresses.
     * @param _token1Amount The amount of token1 to transfer.
     * @param _token0Amount The amount of token0 to transfer.
     * @param _from The address to transfer from.
     * @param _to The address to transfer to.
     */
    function _runTransfers(
        uint _token1Amount,
        uint _token0Amount,
        address _from,
        address _to
    ) internal {
        require(
            IERC20(token0).transferFrom(_from, _to, _token0Amount),
            "Failed to transfer token0"
        );
        require(
            IERC20(token1).transferFrom(_from, _to, _token1Amount),
            "Failed to transfer token1"
        );
    }

    /**
     * @notice Transfers a specified amount of a token between addresses.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     * @param _from The address to transfer from.
     * @param _to The address to transfer to.
     */
    function _runTransfer(
        address _token,
        uint _amount,
        address _from,
        address _to
    ) internal {
        require(
            IERC20(_token).transferFrom(_from, _to, _amount),
            "Failed to transfer tokens"
        );
    }

    /**
     * @notice Returns the contract's address.
     * @return The address of the contract.
     */
    function a() public view returns (address) {
        return address(this);
    }

    function claimTSprofit() public onlyOracle {
        _runTransfer(token1, balance.token1, a(), msg.sender);
        emit TSClaim(balance.token1);
        balance.token1 = 0;
    }
}
