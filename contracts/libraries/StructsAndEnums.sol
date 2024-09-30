// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

contract StructsAndEnums {
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
        uint24 poolFee;
        int24 tickLower;
        int24 tickUpper;
    }

    struct MSOBalance {
        uint token1;
    }

    struct CollatedFees {
        uint token0;
        uint token2;
    }
}
