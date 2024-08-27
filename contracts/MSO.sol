//SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./SynthenticToken.sol";

contract MSO {
    uint256 softcap;
    uint256 hardcap;
    address usdcAddress;

    uint256 ivCount;

    mapping(uint256 => Investment) public investments;
    mapping(address => uint256[]) public investorsInvestments;

    event MSOLaunchInitialized(
        uint256 indexed _investmentId,
        address indexed investor,
        address indexed _enzymeTokenShareAddress
    );
    event MSOLaunchCanceled(
        uint256 indexed _investmentId,
        address indexed investor,
        address indexed _enzymeTokenShareAddress
    );

    constructor(
        uint256 _softcap,
        uint256 _hardcap,
        address _usdcAddress
    ) {
        softcap = _softcap;
        hardcap = _hardcap;
        usdcAddress = _usdcAddress;
    }

    function initializeMSOLaunch(
        address _tsAddress,
        uint256 _tsAmount,
        uint256 _usdcAmount
    ) public {
        //Assert usdc with caps and transfer the ts and usdc
        require(_usdcAmount >= softcap, "USDC amount is less that the soft cap");
        require(
            IERC20(usdcAddress).transferFrom(
                msg.sender,
                address(this),
                _usdcAmount
            ) &&
                IERC20(_tsAddress).transferFrom(
                    msg.sender,
                    address(this),
                    _tsAmount
                ),
            "Transaction failed"
        );
        //Stage the investment
        Investment memory investment = Investment(
            _tsAddress,
            _tsAmount,
            _usdcAmount,
            address(0),
            0,
            msg.sender,
            InvestmentStage.INITIAL
        );
        emit MSOLaunchInitialized(
            _registerInvestment(investment),
            msg.sender,
            _tsAddress
        );
    }

    function executeMSOLaunch(uint256 _investmentId, string calldata _tokenName, string calldata _tokenSymbol) public {
        Investment storage investment = investments[_investmentId];
        assert(investment.investor == msg.sender);
        require(
            investment.investmentStage == InvestmentStage.INITIAL,
            "MSO has already lauched"
        );

        SynthenticToken synthToken = new SynthenticToken(address(this), _tokenName, _tokenSymbol);
        uint tokenAmount = _calculateSyntheticTokenMint(investment.tsAmount);
        synthToken.mint(address(this), tokenAmount);
        investment.tokenAmount = tokenAmount;
        investment.tokenAddress = address(synthToken);
        investment.investmentStage = InvestmentStage.IN_LIQUIDITY_POOL;

        //Provide Liquidity;
    }

    function cancelMSOLaunch(uint256 _investmentId) public {
        Investment storage investment = investments[_investmentId];
        assert(investment.investor == msg.sender);
        require(
            investment.investmentStage == InvestmentStage.INITIAL,
            "MSO has already lauched"
        );
        // Other fun stuff;
        require(
            IERC20(usdcAddress).transferFrom(
                address(this),
                msg.sender,
                investment.usdcAmount
            ) &&
                IERC20(investment.tsAddress).transferFrom(
                    address(this),
                    msg.sender,
                    investment.tsAmount
                ),
            "Transaction failed"
        );
        investment.investmentStage = InvestmentStage.CANCELED;
        emit MSOLaunchCanceled(_investmentId, msg.sender, investment.tsAddress);
    }


    function _calculateSyntheticTokenMint(uint _tsAmount) internal pure returns(uint synthenticTokenAmount){
        synthenticTokenAmount = _tsAmount*10;
    }

    function _registerInvestment(Investment memory _investment)
        internal
        returns (uint256 x)
    {
        investments[ivCount] = _investment;
        investorsInvestments[_investment.investor].push(ivCount);
        x = ivCount;
        ivCount = ivCount + 1;
    }
}

enum InvestmentStage {
    INITIAL,
    IN_LIQUIDITY_POOL,
    CANCELED
}

struct Investment {
    address tsAddress;
    uint256 tsAmount;
    uint256 usdcAmount;
    address tokenAddress;
    uint256 tokenAmount;
    address investor;
    InvestmentStage investmentStage;
}
