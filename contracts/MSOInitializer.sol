// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./interfaces/IComptrollerLib.sol";
import "./interfaces/IVault.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "./MSO.sol";

// Struct to hold the configuration parameters for the MSO //
struct MSOConfig {
    address positionManager; // Address of Uniswap v3 position manager
    address swapRouter; // Address of Uniswap v3 swap router
    address msoLauncher;
    address msoDepositAndWithdraw;
    address msoFeeCollector;
    address msoPriceSync;
    uint minInvestmentToken; // Minimum investment amount
    uint lockPeriod; // Lock period before launch
    uint investmentSoftCap; // Minimum token0 amount required before launch
}

contract MSOInitializer {
    address OracleAddress; // Address of the oracle for authorization
    MSOConfig msoConfig; // Configuration for deploying MSO
    mapping(address => address) public deployedMSO; // Maps vault tokens to deployed MSO contracts

    address[] oracleUpdateAccessList; // List of addresses authorized to update the oracle
    bytes32 oracleUpdatePasscodeHash; // Hash of the passcode required for oracle updates
    address msoImplementation; // The address to the MSO implementation;

    event MSOInitialized(
        address indexed vaultOwner,
        address indexed vaultProxy,
        address indexed MSOAddress
    );

    // Modifier to restrict function access to the oracle address
    modifier onlyOracleAddress() {
        require(OracleAddress == msg.sender, "Caller is not the Oracle");
        _;
    }

    // Modifier to restrict function access to the contract itself
    modifier onlySelf() {
        require(
            address(this) == msg.sender,
            "Caller is not the contract itself"
        );
        _;
    }

    /**
     * @notice Initializes the MSOInitializer contract with the given configuration and oracle settings.
     * @dev Sets the initial oracle address and the MSO configuration parameters. It also sets up the access
     * control list for authorized addresses that can update the oracle and secures the update process with a passcode hash.
     * @param _OracleAddress The address of the oracle server for signature verification.
     * @param _positionManager The address of the Uniswap v3 position manager contract.
     * @param _swapRouter The address of the Uniswap v3 swap router contract.
     * @param _minInvestmentToken The minimum required amount of the investment token for the MSO.
     * @param _lockPeriod The duration (in seconds) for which investments are locked before the MSO launch.
     * @param _investmentSoftCap The soft cap for the investment token before the MSO can launch.
     * @param _oracleUpdateAccessList A list of addresses allowed to update the oracle information.
     * @param _oracleUpdatePasscodeHash The hash of the passcode used for securely updating the oracle address.
     */
    constructor(
        address _OracleAddress,
        address _positionManager,
        address _swapRouter,
        address _msoLauncher,
        address _msoDepositAndWithdraw,
        address _msoFeeCollector,
        address _msoPriceSync,
        uint _minInvestmentToken,
        uint _lockPeriod,
        uint _investmentSoftCap,
        address[] memory _oracleUpdateAccessList,
        bytes32 _oracleUpdatePasscodeHash
    ) {
        // Use storage assignment for efficiency instead of looping
        oracleUpdateAccessList = _oracleUpdateAccessList;

        // Set the hash of the passcode used for secure updates
        oracleUpdatePasscodeHash = _oracleUpdatePasscodeHash;

        // Set the initial oracle address
        OracleAddress = _OracleAddress;

        // Set the initial MSO configurations
        msoConfig = MSOConfig(
            _positionManager,
            _swapRouter,
            _msoLauncher,
            _msoDepositAndWithdraw,
            _msoFeeCollector,
            _msoPriceSync,
            _minInvestmentToken,
            _lockPeriod,
            _investmentSoftCap
        );
    }

    /**
     * @notice Initializes a new MSO contract for a given vault token and investment token.
     * @param _investmentToken The address of the investment token (token0).
     * @param _vaultToken The address of the vault token (token1).
     * @param _r The r component of the signature for oracle authorization.
     * @param _s The s component of the signature for oracle authorization.
     * @param _v The v component of the signature for oracle authorization.
     */
    function initializeMSO(
        address _investmentToken,
        address _vaultToken,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        // Check if MSO is already deployed for a vault token using a cheaper comparison
        require(
            deployedMSO[_vaultToken] == address(0),
            "MSO already initialized"
        );

        // Hash oracle address, tokens, and sender in a more gas-efficient way
        bytes32 hash = keccak256(
            abi.encodePacked(
                OracleAddress,
                _investmentToken,
                _vaultToken,
                msg.sender
            )
        );

        // Use inline assembly for signature recovery to save gas (advanced)
        address signer = ecrecover(hash, _v, _r, _s);

        // Validate that the signer is the oracle
        require(signer == OracleAddress, "Invalid inputs");

        // Cache the `IVault` instance
        IVault vault = IVault(_vaultToken);

        // Check if the investment token is tracked
        require(vault.isTrackedAsset(_investmentToken), "Not a tracked asset");

        // Check if caller is the owner of the vault
        require(
            vault.getOwner() == msg.sender,
            "Only vault owner can initialize MSO"
        );

        // Internal function to deploy the new MSO
        _initializeMSO(_investmentToken, _vaultToken, msg.sender);
    }

    /**
     * @notice Internal function to deploy a new MSO contract.
     * @param _investmentToken The address of the investment token (token0).
     * @param _vaultToken The address of the vault token (token1).
     * @param _vaultOwner The address of the owner of the vault.
     */
    function _initializeMSO(
        address _investmentToken,
        address _vaultToken,
        address _vaultOwner
    ) internal {
        // -------- Deploy MSO ---------//
        MSO mso = new MSO(
            _investmentToken,
            _vaultToken,
            msoConfig.positionManager,
            msoConfig.swapRouter,
            msoConfig.msoLauncher,
            msoConfig.msoDepositAndWithdraw,
            msoConfig.msoFeeCollector,
            msoConfig.msoPriceSync,
            msoConfig.minInvestmentToken,
            msoConfig.lockPeriod,
            msoConfig.investmentSoftCap,
            address(this)
        );

        // Store deployed MSO address in the mapping
        deployedMSO[_vaultToken] = address(mso);

        // Emit event after initializing the MSO
        emit MSOInitialized(_vaultOwner, _vaultToken, address(mso));
    }

    /**
     * @notice Updates the oracle address with a secure passcode.
     * @param _newServerAddress The new address of the oracle server.
     * @param _passcode The passcode to authorize the update.
     * @param _newPasscodeHash The hash of the new passcode for future updates.
     */
    function updateOracleAddress(
        address _newServerAddress,
        string memory _passcode,
        bytes32 _newPasscodeHash
    ) public onlyOracleAddress {
        // Optimize the access check by caching length and breaking the loop early
        bool isAllowed = false;
        uint accessListLength = oracleUpdateAccessList.length;
        for (uint i = 0; i < accessListLength; ++i) {
            if (msg.sender == oracleUpdateAccessList[i]) {
                isAllowed = true;
                break; // Break as soon as we find a match
            }
        }

        // Ensure the caller is on the access list
        require(isAllowed, "Caller not authorized");

        // Verify the passcode by hashing it and comparing it to the stored hash
        bytes32 hash = keccak256(abi.encodePacked(_passcode));
        require(hash == oracleUpdatePasscodeHash, "Invalid passcode");

        // Update the passcode hash for future secure updates
        oracleUpdatePasscodeHash = _newPasscodeHash;

        // Update the oracle address to the new server address
        OracleAddress = _newServerAddress;
    }

    /**
     * @notice Updates the configuration for the MSO contract.
     * @dev This function is restricted to the oracle address specified in the contract.
     * The parameters provided will overwrite the existing configuration.
     * @param _positionManager The address of the new Uniswap v3 position manager.
     * @param _swapRouter The address of the new Uniswap v3 swap router.
     * @param _minInvestmentToken The minimum required investment token amount.
     * @param _lockPeriod The duration for which investments will be locked before launch.
     * @param _investmentSoftCap The soft cap for the investment token before MSO launch.
     */
    function updateMSOConfig(
        address _positionManager,
        address _swapRouter,
         address _msoLauncher,
        address _msoDepositAndWithdraw,
        address _msoFeeCollector,
        address _msoPriceSync,
        uint _minInvestmentToken,
        uint _lockPeriod,
        uint _investmentSoftCap
    ) public onlyOracleAddress {
        // Update the MSO configuration with the new parameters
        msoConfig = MSOConfig(
            _positionManager,
            _swapRouter,
            _msoLauncher,
            _msoDepositAndWithdraw,
            _msoFeeCollector,
            _msoPriceSync,
            _minInvestmentToken,
            _lockPeriod,
            _investmentSoftCap
        );
    }

    /**
     * @notice Retrieves the current oracle address.
     * @return The address of the oracle.
     */
    function getOracleAddress() external view returns (address) {
        // Return the stored oracle address
        return OracleAddress;
    }

    /**
     * @notice Retrieves the liquidity and token amounts associated with a given Uniswap v3 position.
     * @dev Uses the `INonfungiblePositionManager` interface to fetch details of a specific position token ID.
     * The function extracts and returns the liquidity, token0 amount, and token1 amount of the position.
     * @param _positonTokenId The ID of the position token for which the details are being retrieved.
     * @return liquidity The amount of liquidity provided in the Uniswap position.
     * @return token0Amount The amount of token0 held in the position.
     * @return token1Amount The amount of token1 held in the position.
     */
    function getPosition(
        uint _positonTokenId
    )
        external
        view
        returns (uint128 liquidity, uint128 token0Amount, uint128 token1Amount)
    {
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(
                msoConfig.positionManager
            );
        (
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            liquidity,
            ,
            ,
            token0Amount,
            token1Amount
        ) = positionManager.positions(_positonTokenId);
    }
}
