//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./LiquidityManager.sol";

abstract contract MSOProcessingServerEntryPoint is LiquidityManager  {
    constructor () {
        
    }


    function liquidityOperationsEnteryPoint(bytes[] memory _operations) public {
        require(msg.sender == getProcessingServer(), "Only Processing server can call");

        for(uint i; i < _operations.length; i++) {
            (bool success,) = address(this).call(_operations[i]);
            require(success);
        }
    }
}