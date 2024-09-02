// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ONFT721 } from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MyONFT721 is ONFT721, Ownable {
    uint256 private _tokenIdCounter;

    mapping(uint16 => mapping(address => uint256)) public userTokens; // Maps chain ID and user address to token ID

    constructor(address _lzEndpoint) ONFT721("OmnichainSoulboundONFT", "OSBT", _lzEndpoint) {
        _tokenIdCounter = 0;
    }

    // Modifier to ensure tokens are soulbound
    modifier onlyOwnerOf(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        _;
    }

    // Mint a new SBT (only on the current chain)
    function mint(address to, string memory tokenURI) public onlyOwner {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);

        // Record the token for the current chain and user
        userTokens[uint16(block.chainid)][to] = tokenId;
    }

    // Overriding _beforeTokenTransfer to make it soulbound
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ONFT721, ERC721) {
        require(from == address(0) || to == address(0), "This token is soulbound");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // Batch minting across multiple chains
    function batchMint(
        uint16[] memory dstChainIds,
        address[] memory recipients,
        string[] memory tokenURIs
    ) external onlyOwner {
        require(
            dstChainIds.length == recipients.length && recipients.length == tokenURIs.length,
            "Mismatched input lengths"
        );

        for (uint256 i = 0; i < dstChainIds.length; i++) {
            if (dstChainIds[i] == uint16(block.chainid)) {
                // Mint locally if it's the current chain
                mint(recipients[i], tokenURIs[i]);
            } else {
                // Send mint request to other chains
                bytes memory payload = abi.encode(recipients[i], tokenURIs[i]);
                _lzSend(dstChainIds[i], payload, payable(msg.sender), address(0x0), bytes(""));
            }
        }
    }

    // Receiving logic on destination chains
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        (address recipient, string memory tokenURI) = abi.decode(_payload, (address, string));
        mint(recipient, tokenURI);
    }

    // Sync state across chains if needed
    function syncState(uint16 dstChainId, address recipient, uint256 tokenId) external onlyOwnerOf(tokenId) {
        require(dstChainId != uint16(block.chainid), "Cannot sync state within the same chain");
        string memory uri = tokenURI(tokenId);
        bytes memory payload = abi.encode(recipient, uri);
        _lzSend(dstChainId, payload, payable(msg.sender), address(0x0), bytes(""));
    }

    // Function to track user's addresses across chains (for example purposes)
    function trackUserOnMainChain(address user) external view returns (uint256) {
        return userTokens[uint16(block.chainid)][user];
    }

    // Override tokenURI function to make it compatible with ERC721URIStorage
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    // Override supportsInterface to make it compatible with ERC721Enumerable
    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ONFT721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
