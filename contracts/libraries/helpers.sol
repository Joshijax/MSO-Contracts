// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IVault.sol";

library Helpers {
     /**
     * @notice Transfers specified amounts of token0 and token1 between addresses.
     * @param _token1Amount The amount of token1 to transfer.
     * @param _token0Amount The amount of token0 to transfer.
     * @param _from The address to transfer from.
     * @param _to The address to transfer to.
     */
    function runTransfers(
        address _token1,
        address _token0,
        uint _token1Amount,
        uint _token0Amount,
        address _from,
        address _to
    ) external {
        require(IERC20(_token0).transferFrom(_from, _to, _token0Amount));
        require(IERC20(_token1).transferFrom(_from, _to, _token1Amount));
    }

    /**
     * @notice Transfers a specified amount of a token between addresses.
     * @param _token The address of the token to transfer.
     * @param _amount The amount of tokens to transfer.
     * @param _from The address to transfer from.
     * @param _to The address to transfer to.
     */
    function runTransfer(
        address _token,
        uint _amount,
        address _from,
        address _to
    ) external {
        require(IERC20(_token).transferFrom(_from, _to, _amount));
    }


    /**
     * @notice Retrieves the owner of the Enzyme vault.
     * @return The vault owner's address.
     */
    function getVaultOwner(address _token1) external view returns (address) {
        return IVault(_token1).getOwner();
    }
}