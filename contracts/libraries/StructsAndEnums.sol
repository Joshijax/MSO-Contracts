//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

abstract contract StructsAndEnums {
    enum MSOStages {
    BEFORE,
    READY,
    LAUNCHED
}

struct Balance {
    uint token1;
    uint token0;
}

struct LaunchParams {
    uint token2Amount;
    string token2Name;
    string token2Symbol;
    INonfungiblePositionManager.MintParams liquidityParams;
}

}
