//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./LiquidityManager.sol";

abstract contract MSOProcessingServerEntryPoint is LiquidityManager  {
    function liquidityOperationsEnteryPoint(bytes[] memory _operations) public {
        require(msg.sender == getProcessingServer(), "Only Processing server can call");

        for(uint i; i < _operations.length; i++) {
            (bool success,) = address(this).call(_operations[i]);
            require(success);
        }
    }

    function increaseLiquidity(
       INonfungiblePositionManager.IncreaseLiquidityParams memory _params
    ) public onlySelf {
        _increaseLiquidity(_params);
    }


    function decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams memory _params) public onlySelf {
        _decreaseLiquidity(_params);
    }

    function collectFees() public onlySelf {
       _collectFees();
    }

    function swapExactInputSingle(ISwapRouter.ExactInputSingleParams memory _params) public {
        _swapExactInputSingle(_params);
    }
}