// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import { Ownable } from "openzeppelin/access/Ownable.sol";
import { Strings } from "openzeppelin/utils/Strings.sol";
import { IERC165 } from "openzeppelin/utils/introspection/IERC165.sol";
import { IERC721 } from "openzeppelin/token/ERC721/IERC721.sol";


import { ERC721TokenReceiver } from "solmate/tokens/ERC721.sol";

import { ISSMintableNFT } from "./interfaces/ISSMintableNFT.sol";
import { ISSMintWrapperNFT } from "./interfaces/ISSMintWrapperNFT.sol";
import { DummyERC721 } from "./types/DummyERC721.sol";

error TokenAlreadyMinted();
error IndexOutOfBounds();
error TokenDNE();

contract SudoswapMintWrapper is Ownable, DummyERC721, ISSMintWrapperNFT {
    using Strings for uint256;

    event ConsecutiveTransfer(uint256 indexed fromTokenId, uint256 toTokenId, address indexed fromAddress, address indexed toAddress);

    /*//////////////////////////////////////////////////////////////
                        INTERNAL PRIVATE VARIABLES 
    //////////////////////////////////////////////////////////////*/
    // Main NFT contract
    ISSMintableNFT public SSMT;

    // Track who can mint & what tokens have been minted
    mapping(address => bool) private _authorizedMinter;
    
    // Metadata
    string private _baseURI = "";

    // Track the mint quantity 
    uint64 private _tokenIdCap;
    uint64 private _mintedTokenCount;

    address private _registrar;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address ssmt_, uint64 quantity_) DummyERC721("Face of Sudo Mint Wrapper", "FOSMW") {
        // Set the address of the NFT contract where the tokens are being minted from
        SSMT = ISSMintableNFT(ssmt_);

        // Set the mint quantity
        _tokenIdCap = quantity_;
        _registrar  = msg.sender;
        _mintedTokenCount = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        ADMINISTRATIVE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function renameWrapper(string memory name_, string memory symbol_) external onlyOwner {
        name = name_;
        symbol = symbol_;
    }

    function connectWrapperToSSMT(address ssmt_, uint64 quantity_) external onlyOwner {
        // Set the address of the NFT contract where the tokens are being minted from
        SSMT = ISSMintableNFT(ssmt_);

        // Set the mint quantity
        _tokenIdCap = quantity_;

        // Reset minted token counter
        _mintedTokenCount = 0;
    }

    function connectWrapperToPool(address pool_) external onlyOwner {
        _registrar = pool_;
        _authorizedMinter[pool_] = true;
        emit ConsecutiveTransfer(0, _tokenIdCap - _mintedTokenCount, address(0), _registrar);
    }

    function emitBulkTransfer() external onlyOwner {
        emit ConsecutiveTransfer(0, _tokenIdCap - _mintedTokenCount, address(0), _registrar);
    }

    function setBaseURI(string memory baseURI_) external onlyOwner {
        _baseURI = baseURI_;
    }

    function initializeRegistrar() external onlyOwner {
        for (uint index_; index_ < _tokenIdCap; index_ ++) {
            emit Transfer(this.owner(), _registrar, index_);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MINT WRAPPER LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice This accessor function is used to get the parent NFT contract that 
     * this wrapper mints.
     * @return address the contract address of the SSMintableNFT compliant smart cotnract.
     */
    function getMintContract() external returns (address) {
        return address(SSMT);
    }

    /*//////////////////////////////////////////////////////////////
                    ERC721 ENUMERABLE DUMMY LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalSupply() external view override returns (uint256) {
        return 1 + _tokenIdCap - _mintedTokenCount;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view override returns (uint256) {
        if (index >= this.balanceOf(owner)) revert IndexOutOfBounds();
        return index;
    }

    function tokenByIndex(uint256 index) public view override returns (uint256) {
        if (index > this.totalSupply()) revert IndexOutOfBounds();
        return index;
    }

    /*//////////////////////////////////////////////////////////////
                          ERC721 DUMMY LOGIC
    //////////////////////////////////////////////////////////////*/

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (id >= this.totalSupply()) revert TokenDNE();
        return _baseURI;
            // bytes(_baseURI).length > 0
                // ? string(abi.encodePacked(_baseURI, "/", id.toString(), ".json"))
                // : "";
    }

    function ownerOf(uint256 id) public view override(DummyERC721, IERC721) returns (address owner) {
        if (id > this.totalSupply()) revert TokenAlreadyMinted();
        return _registrar;
    }

    function balanceOf(address owner) public view override(DummyERC721, IERC721) returns (uint256) {
        if (owner == _registrar) return _tokenIdCap - _mintedTokenCount;
        return 0;
    }

    function getApproved(uint256) public view override(DummyERC721, IERC721) returns (address) {
        return _registrar;
    }

    function isApprovedForAll(address owner_, address operator_) public view override(DummyERC721, IERC721) returns (bool) {
        if (owner_ == _registrar) return _authorizedMinter[operator_];
        return false;
    }

    function setApprovalForAll(address operator, bool approved) public override(DummyERC721, IERC721) {
        if (!(msg.sender == _registrar || msg.sender == this.owner()))
            return;

        _authorizedMinter[operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }
    
    function approve(address, uint256) public pure override(DummyERC721, IERC721) {
        return;
    }

    /*//////////////////////////////////////////////////////////////
                          MINT & TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override(DummyERC721, IERC721) {
        require(from == _registrar, "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(
            msg.sender == from || this.isApprovedForAll(from, msg.sender) || msg.sender == this.getApproved(id),
            "NOT_AUTHORIZED"
        );

        // Underflow is impossible because tokens are burned on transfer
        unchecked {
            _mintedTokenCount++;
        }

        SSMT.permissionedMint(to);

        emit Transfer(from, address(0), _tokenIdCap - _mintedTokenCount);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public override(DummyERC721, IERC721) {
        transferFrom(from, to, id);

        // Safety check is performed in the permissionedMint function
        // require(
        //     to.code.length == 0 ||
        //         ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, "") ==
        //         ERC721TokenReceiver.onERC721Received.selector,
        //     "UNSAFE_RECIPIENT"
        // );
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata
    ) public override(DummyERC721, IERC721) {
        transferFrom(from, to, id);

        // Safety check is performed in the permissionedMint function
        // require(
        //     to.code.length == 0 ||
        //         ERC721TokenReceiver(to).onERC721Received(msg.sender, from, id, data) ==
        //         ERC721TokenReceiver.onERC721Received.selector,
        //     "UNSAFE_RECIPIENT"
        // );
    }

    /*//////////////////////////////////////////////////////////////
                        INTROSPECTION LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(DummyERC721, IERC165) returns (bool) {
        return
        interfaceId == type(ISSMintWrapperNFT).interfaceId ||
        super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                            CLEANUP LOGIC
    //////////////////////////////////////////////////////////////*/

    function destroy() external onlyOwner {
        selfdestruct(payable(msg.sender));
    }
}
