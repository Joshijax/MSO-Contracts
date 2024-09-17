//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

abstract contract StructsAndEnums {
    struct Cap {
        uint soft;
        uint hard;
    }
    struct Balance {
        uint usdc;
        uint ts;
    }

    enum MSOStage {
        INIT,
        LIQUIDITY,
        CANCELED
    }

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    struct SyntheticTokenConfig {
        string name;
        string symbol;
    }

    struct InLiquidity {
        uint usdc;
        uint synth;
    }
}
