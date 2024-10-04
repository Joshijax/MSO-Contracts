// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IComptrollerLib.sol";
import "../interfaces/IVault.sol";

library EnzymeHelper {
    using SafeMath for uint;

    function buySharesFromEnzyme(
        address _token0,
        address _token1,
        uint _token0Amount,
        uint _minToken1Quantity,
        address _recipient
    ) internal returns (uint token1Amount_) {
        address comptrollerAddress = IVault(_token1).getAccessor();
        require(IERC20(_token0).approve(comptrollerAddress, _token0Amount));

        // Buy shares from the Enzyme vault
        token1Amount_ = IComptrollerLib(comptrollerAddress).buyShares(
            _recipient,
            _token0Amount,
            _minToken1Quantity
        );
    }

    function redeemInvestmentFromEnzyme(
        address _token1,
        uint256 _token1Amount,
        address _recipient,
        address[] memory _assetsToWithdraw,
        uint[] memory _percentages
    ) internal returns (uint token0Amount_) {
        address comptrollerAddress = IVault(_token1).getAccessor();
        require(IERC20(_token1).approve(comptrollerAddress, _token1Amount));

        // Redeem specific assets from Enzyme based on shares
        token0Amount_ = IComptrollerLib(comptrollerAddress)
            .redeemSharesForSpecificAssets(
                _recipient,
                _token1Amount,
                _assetsToWithdraw,
                _percentages
            )[0];
    }
}
