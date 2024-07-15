// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol";
import "./ERC6909.sol";

enum AssetType {
    _____,
    ERC20,
    ERC721,
    ERC1155
}

struct AssetMetadata {
    string name;
    string symbol;
    AssetType assetType;
}


contract UTC is ERC6909, IERC1155Receiver {
    error ERC20TransferFailed(address token, uint256 amount);
    
    event FungibleAssetCreated(string indexed name, string indexed symbol, uint indexed assetTip, uint totalSupply);
    event NonFungibleAssetCreated(string indexed name, string indexed symbol, uint indexed assetTip, uint totalSupply);
    event NonFungibleAssetMinted(uint indexed assetTip, uint indexed assetId);

    event ERC20Registered(address indexed token, uint indexed assetId);
    event ERC721Registered(address indexed token, uint indexed assetTip);
    event ERC1155Registered(address indexed token, uint indexed assetTip);



    uint public nextTip;
    mapping(uint assetTip => AssetMetadata assetMetadata) public assetMetadatas;
    mapping(uint assetId => string tokenURI) public tokenURI;
    mapping(uint assetTip => address creator) public creatorOf;
    mapping(uint assetId => address owner) public ownerOf;

    mapping(uint assetId => bool canWrap) public wrapperRegistry;



    // Public fn(s)

    /// @notice Creates an NFT asset.
    /// @param name The name of the asset.
    /// @param symbol The token symbol.
    /// @param ts the proposed total supply of the token.
    function createNonFungibleAsset(string calldata name, string calldata symbol, uint ts) public {
        AssetMetadata memory a = AssetMetadata(name, symbol, AssetType.ERC721);
        uint assetTip = nextTip;
        totalSupply[assetTip] = ts;
        assetMetadatas[assetTip] = a;
        creatorOf[assetTip] = msg.sender;
        nextTip+=(ts+1);
        emit NonFungibleAssetCreated(name, symbol, assetTip, ts);
    }

 
    /// @notice Creates a fungible asset.
    /// @param name The name of the asset.
    /// @param symbol The token symbol.
    /// @param ts the proposed total supply of the token.
    /// @param mintTo the proposed account to hold token supply.
    function createFungibleAsset(string calldata name, string calldata symbol, uint ts, address mintTo) public {
        AssetMetadata memory a = AssetMetadata(name, symbol, AssetType.ERC20);
        uint assetTip = nextTip;
        totalSupply[assetTip] = ts;
        assetMetadatas[assetTip] = a;
        balanceOf[mintTo][assetTip]=ts;
        creatorOf[assetTip] = msg.sender;
        nextTip+=1;
        emit FungibleAssetCreated(name, symbol, assetTip, ts);
    }

    /// @notice Mints a Nonfungible asset. This is left the the Implementing contract to override
    /// @param assetTip The NFT asset identifier.
    /// @param tokenId The NFT to be minted.
    /// @param tokenURI_ The token URI for metadata.
    /// @param to The recipient account.
    function mintNonFungibleAsset(uint assetTip, uint tokenId, string calldata tokenURI_, address to) public {
        _mintNonFungibleAsset(assetTip, tokenId, tokenURI_, to);
    }


    /// @notice Registers ERC20 token for wrapping.
    /// @param token The NFT contract.
    function registerERC20(address token) public {
        uint256 assetId = uint256(uint160(token));
        wrapperRegistry[assetId] = true;
        emit ERC20Registered(token, assetId);
    }

    /// @notice Registers ERC20 token for wrapping.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id.
    function registerERC721(address token, uint originalTokenId) public {
        uint256 assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        wrapperRegistry[assetId] = true;
        emit ERC721Registered(token, assetId);
    }

    /// @notice Registers ERC20 token for wrapping.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id.
    function registerERC1155(address token, uint originalTokenId) public {
        uint256 assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        wrapperRegistry[assetId] = true;
        emit ERC1155Registered(token, assetId);
    }


    /// @notice Wraps an ERC721 token.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id to be wrapped from the contract.
    function wrapERC721(address token, uint originalTokenId) public {
        uint assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        string memory name = IERC721Metadata(token).name();
        string memory symbol = IERC721Metadata(token).symbol();
        balanceOf[msg.sender][assetId] = 1;
        totalSupply[assetId] = 1;
        assetMetadatas[assetId] = AssetMetadata(name, symbol, AssetType.ERC721);
        tokenURI[assetId] = IERC721Metadata(token).tokenURI(originalTokenId);
        ownerOf[assetId] = msg.sender;
        IERC721Metadata(token).transferFrom(msg.sender, address(this), originalTokenId);
    }

    /// @notice Wraps an ERC1155 token.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id to be wrapped from the contract.
    function wrapERC1155(address token, uint originalTokenId, uint amount) public {
        uint assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        balanceOf[msg.sender][assetId] += amount;
        totalSupply[assetId] += amount;
        //ERC1155 do not have names and symbols onchain
        assetMetadatas[assetId] = AssetMetadata("", "", AssetType.ERC1155);
        tokenURI[assetId] = IERC1155MetadataURI(token).uri(originalTokenId);
        ownerOf[assetId] = msg.sender;
        IERC1155MetadataURI(token).safeTransferFrom(msg.sender, address(this), originalTokenId, amount, "");
    }


    /// @notice Wraps an ERC20 token.
    /// @param token The NFT contract.
    /// @param amount The amount of tokens to be wrapped
    function wrapERC20(address token, uint amount) public {
        uint256 assetId = uint256(uint160(token));
        string memory name = IERC20Metadata(token).name();
        string memory symbol = IERC20Metadata(token).symbol();
        balanceOf[msg.sender][assetId] += amount;
        totalSupply[assetId]+=amount;
        assetMetadatas[assetId] = AssetMetadata(name, symbol, AssetType.ERC20);
        if (!IERC20Metadata(token).transferFrom(msg.sender, address(this), amount)) {
            revert ERC20TransferFailed(token, amount);
        }
    }

    /// @notice Unwraps an ERC20 token.
    /// @param token The NFT contract.
    /// @param amount The amount of tokens to be unwrapped
    function unwrapERC20(address token, uint amount) public {
        uint256 assetId = uint256(uint160(token));
        balanceOf[msg.sender][assetId] -= amount;
        totalSupply[assetId]-=amount;
        if (!IERC20Metadata(token).transfer(msg.sender, amount)) {
            revert ERC20TransferFailed(token, amount);
        }
    }
    
    /// @notice unwraps an ERC721 token.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id to be unwrapped from the contract.
    function unwrapERC721(address token, uint originalTokenId) public {
        uint assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        balanceOf[msg.sender][assetId] -= 1;
        totalSupply[assetId]-=1;
        ownerOf[assetId] = address(0);
        IERC721Metadata(token).transferFrom(address(this), msg.sender, originalTokenId);
    }

    /// @notice unwraps an ERC721 token.
    /// @param token The NFT contract.
    /// @param originalTokenId The NFT id to be unwrapped from the contract.
    function unwrapERC1155(address token, uint originalTokenId, uint amount) public {
        uint assetId = uint256(keccak256(abi.encodePacked(token, originalTokenId)));
        balanceOf[msg.sender][assetId] -= amount;
        totalSupply[assetId]-=amount;
        ownerOf[assetId] = address(0);
        IERC1155MetadataURI(token).safeTransferFrom(address(this), msg.sender, originalTokenId, amount, "");
    }

    //view fn(s)
    /// @notice Gets the local identifier of a wrapped token.
    /// @param token The token contract.
    /// @param originalTokenId The token id. if fungible, the passed value will be ignored
    function getWrappedAssetId(address token, uint originalTokenId, bool isFungible) public pure returns(uint assetId) {
        assetId = isFungible? uint256(uint160(token)) : uint256(keccak256(abi.encodePacked(token, originalTokenId)));
    }

    // Internal fn(s)
    /// @notice The main Mint function. Mints a Nonfungible asset.
    /// @param assetTip The NFT asset identifier.
    /// @param tokenId The NFT to be minted.
    /// @param tokenURI_ The token URI for metadata.
    /// @param to The recipient account.
    function _mintNonFungibleAsset(uint assetTip, uint tokenId, string memory tokenURI_, address to) internal {
        require(assetMetadatas[assetTip].assetType == AssetType.ERC721, "This asset is not an NFT");
        uint assetId = assetTip + tokenId;
        require(ownerOf[assetId] == address(0x0), "This asset is already owned");
        require(assetId <= assetTip + totalSupply[assetTip], "Asset member exceeded");
        require(assetId != assetTip, "An asset tip is only an identifier and cannot be owned as an asset");
        balanceOf[to][assetTip]++;
        tokenURI[assetId] = tokenURI_;
        ownerOf[assetId] = to;
        emit NonFungibleAssetMinted(assetTip, assetId);
    }






    function onERC1155Received(address operator, address from, uint256 originalTokenId, uint256 amount, bytes calldata)
        public
        returns (bytes4)
    {
        if (operator != address(this)) {
            wrapERC1155(from, originalTokenId, amount);
        }

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata originalTokenIds,
        uint256[] calldata amounts,
        bytes calldata
    ) public returns (bytes4) {
        if (operator != address(this)) {
            for (uint256 i; i < originalTokenIds.length; ++i) {
                wrapERC1155(from, originalTokenIds[i], amounts[i]);
            }
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
}