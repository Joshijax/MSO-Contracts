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
import "./MSOInitStage.sol";

contract MSO is IERC721Receiver, StructsAndEnums {
    using SafeMath for uint256;
    using SafeMath for uint128;

    ////////////////////////////
    /// Liquidity State  ///////
    ////////////////////////////
    INonfungiblePositionManager public positionManager;
    ISwapRouter public swapRouter;
    MSOBalance public balance;
    CollatedFees public fees;
    address[] token1ToWithdraw = [token1];
    uint[] percentageToWithdraw = [100];
    uint24 public uniswapPoolFee = 10000;
    uint public positionTokenId;

    ////////////////////////////
    //// Token State  //////////
    ////////////////////////////
    address public token0; // enzyme vault investment token
    address public token1; // enzyme vault token (TS)
    address public token2; // Synthetic token
    uint public minToken0;

    address public msoInitializer;
    MSOInitStage public msoInitStage;

    ///////////////////////////
    //// Deposit State ////////
    ///////////////////////////
    uint public token0Balance;
    uint public token1Balance;

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
     * @param _launchParams The parameters required for the launch.
     */
    constructor(
        address _token0,
        address _token1,
        address _positionManager,
        address _swapRouter,
        uint _minToken0,
        LaunchParams memory _launchParams
    ) {
        token0 = _token0;
        token1 = _token1;
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        minToken0 = _minToken0;

        msoInitStage = MSOInitStage(msg.sender);

        _launch(_launchParams);
    }

    /**
     * @notice Collects fees accrued from the Uniswap liquidity position and distributes them proportionally to investors.
     */
    function collectFees() external {
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

        require(fees.token0 != 0 && getInvestorsBalance(msg.sender).token0 != 0);

        // Calculate fees owed to the caller based on their share of token0
        uint fee0 = (
            getInvestorsBalance(msg.sender).token0.mul(fees.token0).div(
                token0Balance
            )
        );
        uint fee2 = (
            getInvestorsBalance(msg.sender).token0.mul(fees.token2).div(
                token0Balance
            )
        );

        // Deduct collected fees
        fees.token0 = fees.token0.sub(fee0);
        fees.token2 = fees.token0.sub(fee2);

        // Transfer fees to the caller
        Helpers.runTransfer(token0, fee0, a(), msg.sender);
        Helpers.runTransfer(token2, fee2, a(), msg.sender);
    }

    function depositAfterLaunch(uint _maxToken0Amount) external {
        (, uint token0Owed, uint token2Owed) = MSOInitializer(msoInitializer).getPosition(
            address(positionManager),
            positionTokenId
        );

        uint maxToken2Amount = token2Owed.mul(_maxToken0Amount).div(token0Owed);

        Helpers.runTransfers(
            token1, token0,
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
            Helpers.runTransfers(
                token1, token0,
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
        uint token0Amount = getInvestorsBalance(msg.sender).token0;
        assert(token0Amount != 0);

        // Get liquidity info for the position
        (
            uint128 liquidity,
            uint128 token0Owed,
            uint128 token1Owed
        ) = MSOInitializer(msoInitializer).getPosition(
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
        Helpers.runTransfer(
            token0,
            withdrawableToken0Amount.mul(_tokenPercentage).div(100),
            a(),
            msg.sender
        );
        Helpers.runTransfer(
            token1,
            getInvestorsBalance(msg.sender).token1.mul(_tokenPercentage).div(100),
            a(),
            msg.sender
        );
        Helpers.runTransfer(
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
            _token0Amount.mul(10 ** ERC20(token1).decimals()).div(
                10 ** ERC20(token0).decimals()
            );
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

        emit Launched(token2Amount, token0Amount);
    }

    /**
     * @notice Synchronizes the prize by adjusting the amount of token1 in the contract.
     * @param _token1Amount The amount of token1 to adjust.
     */
    function syncPrizeUp(uint _token1Amount) external onlyOracle {
        require(_token1Amount <= balance.token1);

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
        balance.token1 = balance.token1.add(
            buySharesFromEnzyme(token0Amount, 0)
        );
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
        require(IERC20(token0).approve(comptrollerAddress, _token0Amount));

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
        require(IERC20(token1).approve(comptrollerAddress, _token1Amount));

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
     * @notice Returns the contract's address.
     * @return The address of the contract.
     */
    function a() public view returns (address) {
        return address(this);
    }

    function claimTSprofit() public onlyOracle {
        Helpers.runTransfer(token1, balance.token1, a(), msg.sender);
        emit TSClaim(balance.token1);
        balance.token1 = 0;
    }

    function getInvestorsBalance(address _investor) internal view returns(Balance memory){
        return msoInitStage.getInvestmentBalance(_investor);
    }
}
