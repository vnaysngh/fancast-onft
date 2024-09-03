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
        address[] joinedCommunities; // List of joined communities
    }

    mapping(address => bool) public _hasToken;
    mapping(address => UserInfo) public userInfo;
    mapping(address => address[]) public communityMembers; // Maps an original NFT contract to the list of users holding ONFTs
    mapping(address => uint256) public communityCount; // Maps an original NFT contract to the count of members

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) ONFT721(_name, _symbol, _lzEndpoint, _delegate) {}

    // Function to mint NFT for first-time users and join their first community
    function mintNFTAndJoinCommunity(address to, address originalNFTContract) public onlyOwner {
        require(to != address(0), "Invalid address");
        require(originalNFTContract != address(0), "Invalid community address");
        require(!_hasToken[to], "User already has an NFT");
        // require(userInfo[to].tokenId == 0, "Inconsistent state: User marked as not having a token, but has tokenId");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _safeMint(to, tokenId);

        // Mark that the user now has a token
        _hasToken[to] = true;

        // Initialize the user info with the first community
        userInfo[to] = UserInfo({ tokenId: tokenId, isActive: true, joinedCommunities: new address[](1) });
        userInfo[to].joinedCommunities[0] = originalNFTContract;

        // Update community members and count
        communityMembers[originalNFTContract].push(to);
        communityCount[originalNFTContract]++;

        emit NFTMintedAndCommunityJoined(to, originalNFTContract, tokenId);
    }

    // Function for existing NFT holders to join additional communities
    function joinAdditionalCommunity(address to, address originalNFTContract) public onlyOwner {
        require(to != address(0), "Invalid address");
        require(originalNFTContract != address(0), "Invalid community address");
        require(_hasToken[to], "User does not have an NFT");

        // Check if the user has already joined this community
        bool alreadyJoined = false;
        for (uint256 i = 0; i < userInfo[to].joinedCommunities.length; i++) {
            if (userInfo[to].joinedCommunities[i] == originalNFTContract) {
                alreadyJoined = true;
                break;
            }
        }
        require(!alreadyJoined, "User has already joined this community");

        // Add the new community
        userInfo[to].joinedCommunities.push(originalNFTContract);

        // Update community members and count
        communityMembers[originalNFTContract].push(to);
        communityCount[originalNFTContract]++;

        emit AdditionalCommunityJoined(to, originalNFTContract, userInfo[to].tokenId);
    }

    // Events to emit when a user mints an NFT and joins their first community
    event NFTMintedAndCommunityJoined(address indexed user, address indexed community, uint256 tokenId);

    // Event to emit when an existing NFT holder joins an additional community
    event AdditionalCommunityJoined(address indexed user, address indexed community, uint256 tokenId);

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
        address[] memory joinedCommunities = userInfo[user].joinedCommunities;

        _burn(tokenId);

        // Remove user from all joined communities
        for (uint256 i = 0; i < joinedCommunities.length; i++) {
            address community = joinedCommunities[i];
            address[] storage members = communityMembers[community];
            for (uint256 j = 0; j < members.length; j++) {
                if (members[j] == user) {
                    members[j] = members[members.length - 1];
                    members.pop();
                    communityCount[community]--;
                    break;
                }
            }
        }

        delete userInfo[user];
    }

    // Get all members of a community
    function getCommunityMembers(address originalNFTContract) public view returns (address[] memory) {
        return communityMembers[originalNFTContract];
    }

    // Get user info, including joined communities
    function getUserInfo(address user) public view returns (UserInfo memory) {
        return userInfo[user];
    }

    // Get community count for a specific community
    function getCommunityCount(address originalNFTContract) public view returns (uint256) {
        return communityCount[originalNFTContract];
    }
}
