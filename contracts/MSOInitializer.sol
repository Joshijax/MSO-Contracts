//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
import "./libraries/Events.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token";

contract MSOInitializer is Events {
    address OracleAddress;
    mapping(address => address) public deployedMSO;

    address[] oracleUpdateAccessList;
    byte32 oracleUpdatePasscodeHash;

    modifier onlyOracleAddress() {
        require(OracleAddress == msg.sender);
        _;
    }

    modifier onlySelf() {
        require(address(this) == msg.sender);
        _;
    }

    constructor(address _OracleAddress, address[] _oracleUpdateAccessList, byte32 _oracleUpdatePasscodeHash) {
        oracleUpdateAccessList = _oracleUpdateAccessList;
        oracleUpdatePasscodeHash = _oracleUpdatePasscodeHash;
        OracleAddress = _OracleAddress;
    }

    function initializeMSO(
        address _vaultOwner,
        address _vaultProxy,
        bytes32 _r,
        bytes32 _s,
        uint8 _v
    ) public {
        require(deployedMSO[_vaultProxy] == address(0), "MSO has already been initialized");
        bytes32 hash = keccak256(abi.encodePacked(OracleAddress, _vaultOwner, _vaultProxy));
        address signer = ecrecover(hash, _v, _r, _s);

        require(signer == OracleAddress, "Invalid inputs");
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
        emit MSOInitialized(_vaultOwner, _vaultProxy, deployedMSO[_vaultProxy]);
    }

    function updateOracleAddress(address _newServerAddress, string memory _passcode, byte32 _newPasscodeHash) public onlyOracleAddress {
        bool isAllowed;
        for(uint i; i<oracleUpdateAccessList.length; i++){
            if(msg.sender == oracleUpdateAccessList[i]){
                isAllowed = true;
                break;
            }
        }

        assert(isAllowed);

        byte32 hash = keccak256(abi.encodePacked(_passcode));
        assert(hash == oracleUpdatePasscodeHash);
        oracleUpdatePasscodeHash = _newPasscodeHash;
        OracleAddress = _newServerAddress;
    }

    function getOracleAddress() external view returns(address) {
        return OracleAddress;
    }
}
