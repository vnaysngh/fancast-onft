// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ONFT721 } from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract MyONFT721 is ONFT721 {
    uint256 private _tokenIdCounter;
    using OptionsBuilder for bytes;
    bytes options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

    struct UserInfo {
        uint256 tokenId;
        bool isActive;
        address originalNFTContract; // Address of the original NFT contract (e.g., BAYC)
    }

    mapping(address => UserInfo) public userInfo;
    mapping(address => address[]) public communityMembers; // Maps an original NFT contract to the list of users holding ONFTs
    mapping(address => uint256) public communityCount; // Maps an original NFT contract to the count of members

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) ONFT721(_name, _symbol, _lzEndpoint, _delegate) {}

    // Mint a new ONFT and set it as active, associating it with the original NFT contract
    function mint(address to, address originalNFTContract) public onlyOwner {
        require(userInfo[to].tokenId == 0, "User already has a token");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;

        _safeMint(to, tokenId);

        userInfo[to] = UserInfo(tokenId, true, originalNFTContract);

        // Add the user to the community members list
        communityMembers[originalNFTContract].push(to);
        communityCount[originalNFTContract]++;
    }

    // Deactivate user's token
    function deactivate(address user) public {
        require(msg.sender == user || msg.sender == owner(), "Not authorized");
        require(userInfo[user].tokenId != 0, "User has no token");

        userInfo[user].isActive = false;
    }

    // Reactivate user's token
    function reactivate(address user) public {
        require(msg.sender == user || msg.sender == owner(), "Not authorized");
        require(userInfo[user].tokenId != 0, "User has no token");

        userInfo[user].isActive = true;
    }

    // Delete user's token and remove them from the community list
    function deleteToken(address user) public onlyOwner {
        require(userInfo[user].tokenId != 0, "User has no token");

        uint256 tokenId = userInfo[user].tokenId;
        address originalNFTContract = userInfo[user].originalNFTContract;

        _burn(tokenId);

        // Remove user from communityMembers list
        address[] storage members = communityMembers[originalNFTContract];
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == user) {
                members[i] = members[members.length - 1];
                members.pop();
                communityCount[originalNFTContract]--;
                break;
            }
        }

        delete userInfo[user];
    }

    // Get all members of a community (e.g., holders of BAYC who have minted an ONFT)
    function getCommunityMembers(address originalNFTContract) public view returns (address[] memory) {
        return communityMembers[originalNFTContract];
    }

    // Batch minting across multiple chains for a single user
    function batchMint(uint16[] memory dstChainIds, address to) external payable onlyOwner {
        // Mint locally for the recipient
        mint(to);

        // Send mint request to other chains
        bytes memory payload = abi.encode(to);
        for (uint256 i = 0; i < dstChainIds.length; i++) {
            _lzSend(dstChainIds[i], payload, options, MessagingFee(msg.value, 0), payable(msg.sender));
        }
    }

    function _lzReceive(Origin calldata, bytes32, bytes calldata payload, address, bytes calldata) internal override {
        (address recipient, address originalNFTContract) = abi.decode(payload, (address, address));
        mint(recipient, originalNFTContract);
    }

    function quote(address to, uint32[] memory _dstChainIds) public view returns (MessagingFee memory totalFee) {
        bytes memory payload = abi.encode(to);

        for (uint i = 0; i < _dstChainIds.length; i++) {
            MessagingFee memory fee = _quote(_dstChainIds[i], payload, options, false);
            totalFee.nativeFee += fee.nativeFee;
            totalFee.lzTokenFee += fee.lzTokenFee;
        }

        return totalFee;
    }
}
