//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
import "./libraries/Events.sol";

contract MSOInitializer is Events {
    address MSOServer;
    mapping(address => address) public deployedMSO;

    modifier onlyMSOServer() {
        require(MSOServer == msg.sender);
        _;
    }

    modifier onlySelf() {
        require(address(this) == msg.sender);
        _;
    }

    constructor(address _MSOServer) {
        MSOServer = _MSOServer;
    }

    function initializeMSO(
        address _vaultOwner,
        address _vaultProxy,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        require(deployedMSO[_vaultProxy] == address(0), "MSO has already been initialized");
        bytes32 hash = keccak256(abi.encodePacked(MSOServer, _vaultOwner, _vaultProxy));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == MSOServer, "Invalid inputs");
        require(_vaultOwner == msg.sender, "Only verified vaultOwners can Initialize MSO");
        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("_initializeMSO(address,address,address)")), _vaultOwner, _vaultProxy);
        (bool success, ) = address(this).call(data);
        require(success);
    }

    function _initializeMSO(
        address _vaultOwner,
        address _vaultProxy
    ) public onlySelf {
        // -------- Depoly MSO ---------//
        deployedMSO[_vaultProxy] = address(0);
        emit MSOInitialized(_vaultOwner, _vaultProxy);
    }

    function updateMSOServer(address _newServerAddress) public onlyMSOServer {
        MSOServer = _newServerAddress;
    }

    function getProcessingServer() external view returns(address) {
        return MSOServer;
    }
}
