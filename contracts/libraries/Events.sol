//SPDX-License-Identifier: MIT
pragma solidity >=0.7.6;

abstract contract Events {
    event TokenSharesStaked(
        address indexed staker,
        address indexed vaultProxy,
        address indexed tsAddress,
        uint usdcAmount,
        uint tsAmount
    );

    event MSOCanceled(
        address indexed vaultProxy,
        address indexed tsAddress
    );

    event MSOLaunched(
        address indexed vaultProxy,
        address indexed tsAddress,
        address indexed synthTokenAddress
    );

    event MSOInitialized(address indexed vaultOwner, address indexed vaultProxy);
}
