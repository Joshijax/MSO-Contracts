// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;


interface IVault {
    function getAccessor() external view returns (address);

    function getOwner() external view returns (address);

    function isTrackedAsset(address _asset) external view returns (bool);
}