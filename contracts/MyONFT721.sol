// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ONFT721 } from "@layerzerolabs/onft-evm/contracts/onft721/ONFT721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import { MessagingFee, Origin } from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { ISP } from "@ethsign/sign-protocol-evm/src/interfaces/ISP.sol";
import { Attestation } from "@ethsign/sign-protocol-evm/src/models/Attestation.sol";
import { DataLocation } from "@ethsign/sign-protocol-evm/src/models/DataLocation.sol";

contract MyONFT721 is ONFT721 {
    uint256 private _tokenIdCounter;
    using OptionsBuilder for bytes;
    bytes options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

    ISP public spInstance;
    uint64 public schemaId;

    struct UserInfo {
        uint256 tokenId;
        bool isActive;
        address[] joinedCommunities; // List of joined communities
        uint64 attestationId;
    }

    struct CommunityInfo {
        uint256 communityCount;
        address[] communityMembers; // List of community members
    }

    mapping(address => bool) public hasToken;
    mapping(address => UserInfo) public userInfo;
    mapping(address => CommunityInfo) public communityInfo;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) ONFT721(_name, _symbol, _lzEndpoint, _delegate) {}

    function setSPInstance(address instance) external onlyOwner {
        spInstance = ISP(instance);
    }

    // New function to create attestation
    function createAttestation(bytes memory data) public {
        // require(hasToken[msg.sender], "User does not have an NFT");

        bytes[] memory recipients = new bytes[](1);
        recipients[0] = abi.encode(msg.sender);

        Attestation memory a = Attestation({
            schemaId: schemaId,
            linkedAttestationId: 0,
            attestTimestamp: 0,
            revokeTimestamp: 0,
            attester: address(this),
            validUntil: 0,
            dataLocation: DataLocation.ONCHAIN,
            revoked: false,
            recipients: recipients,
            data: data // SignScan assumes this is from `abi.encode(...)`
        });

        uint64 attestationId = spInstance.attest(a, "", "", "");
        userInfo[msg.sender].attestationId = attestationId;

        // emit AttestationCreated(msg.sender, string(abi.encodePacked(attestationId)));
    }

    function setSchemaID(uint64 schemaId_) external onlyOwner {
        schemaId = schemaId_;
    }

    // Modified implementation to allow user minting:
    function mintNFTAndJoinCommunity(address originalNFTContract) public {
        require(originalNFTContract != address(0), "Invalid community address");
        require(!hasToken[msg.sender], "User already has an NFT");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _safeMint(msg.sender, tokenId);

        // Mark that the user now has a token
        hasToken[msg.sender] = true;

        // Initialize the user info with the first community
        userInfo[msg.sender] = UserInfo({
            tokenId: tokenId,
            isActive: true,
            joinedCommunities: new address[](1),
            attestationId: 0
        });
        userInfo[msg.sender].joinedCommunities[0] = originalNFTContract;

        // Update community info
        communityInfo[originalNFTContract].communityMembers.push(msg.sender);
        communityInfo[originalNFTContract].communityCount++;

        emit NFTMintedAndCommunityJoined(msg.sender, originalNFTContract, tokenId);
    }

    // Function to mint NFT for first-time users and join their first community
    function ownerMintNFTAndJoinCommunity(address to, address originalNFTContract) public onlyOwner {
        require(to != address(0), "Invalid address");
        require(originalNFTContract != address(0), "Invalid community address");
        require(!hasToken[to], "User already has an NFT");

        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        _safeMint(to, tokenId);

        // Mark that the user now has a token
        hasToken[to] = true;

        // Initialize the user info with the first community
        userInfo[to] = UserInfo({
            tokenId: tokenId,
            isActive: true,
            joinedCommunities: new address[](1),
            attestationId: 0
        });
        userInfo[to].joinedCommunities[0] = originalNFTContract;

        // Update community info
        communityInfo[originalNFTContract].communityMembers.push(to);
        communityInfo[originalNFTContract].communityCount++;

        emit NFTMintedAndCommunityJoined(to, originalNFTContract, tokenId);
    }

    // Events
    event DataUpdateInitiated(address indexed initiator, uint32[] destinationChainIds);
    event DataUpdateReceived(uint16 srcChainId);

    // Function to update all relevant data across all chains
    function updateDataAcrossChains(uint32[] memory _dstChainIds) external payable {
        require(hasToken[msg.sender], "User does not have an NFT");

        MessagingFee memory totalFee = quote(_dstChainIds);
        require(msg.value >= totalFee.nativeFee, "Insufficient fee provided");

        // Prepare the payload with relevant data
        (
            address[] memory communities,
            uint256[] memory communityCounts,
            address[][] memory communityMembers
        ) = getRelevantCommunityInfo(msg.sender);

        bytes memory payload = abi.encode(
            msg.sender,
            hasToken[msg.sender],
            userInfo[msg.sender].tokenId,
            userInfo[msg.sender].isActive,
            userInfo[msg.sender].joinedCommunities,
            userInfo[msg.sender].attestationId,
            communities,
            communityCounts,
            communityMembers
        );

        uint256 totalNativeFeeUsed = 0;
        uint256 remainingValue = msg.value;

        for (uint i = 0; i < _dstChainIds.length; i++) {
            MessagingFee memory fee = _quote(_dstChainIds[i], payload, options, false);
            totalNativeFeeUsed += fee.nativeFee;
            remainingValue -= fee.nativeFee;
            require(remainingValue >= 0, "Insufficient fee for this destination");

            _lzSend(_dstChainIds[i], payload, options, MessagingFee(fee.nativeFee, 0), payable(msg.sender));
        }

        emit DataUpdateInitiated(msg.sender, _dstChainIds);
    }

    // Helper function to get relevant community info for a user
    function getRelevantCommunityInfo(
        address user
    )
        internal
        view
        returns (address[] memory communities, uint256[] memory communityCounts, address[][] memory communityMembers)
    {
        communities = userInfo[user].joinedCommunities;
        communityCounts = new uint256[](communities.length);
        communityMembers = new address[][](communities.length);

        for (uint i = 0; i < communities.length; i++) {
            communityCounts[i] = communityInfo[communities[i]].communityCount;
            communityMembers[i] = communityInfo[communities[i]].communityMembers;
        }

        return (communities, communityCounts, communityMembers);
    }

    // Function to receive and process the data update on the destination chain
    function _lzReceive(Origin calldata, bytes32, bytes calldata _payload, address, bytes calldata) internal override {
        (
            address user,
            bool _hasToken,
            uint256 tokenId,
            bool isActive,
            uint64 _attestationId,
            address[] memory joinedCommunities,
            address[] memory communities,
            uint256[] memory communityCounts,
            address[][] memory communityMembers
        ) = abi.decode(_payload, (address, bool, uint256, bool, uint64, address[], address[], uint256[], address[][]));

        // Update hasToken
        hasToken[user] = _hasToken;

        // Update userInfo
        userInfo[user].tokenId = tokenId;
        userInfo[user].isActive = isActive;
        userInfo[user].joinedCommunities = joinedCommunities;
        userInfo[user].attestationId = _attestationId;

        // Update communityInfo
        for (uint i = 0; i < communities.length; i++) {
            communityInfo[communities[i]].communityCount = communityCounts[i];
            communityInfo[communities[i]].communityMembers = communityMembers[i];
        }

        // emit DataUpdateReceived(_origin.srcChainId);
    }

    function quote(uint32[] memory _dstChainIds) public view returns (MessagingFee memory totalFee) {
        require(hasToken[msg.sender], "User does not have an NFT");
        require(_dstChainIds.length > 0, "No destination chains provided");

        (
            address[] memory communities,
            uint256[] memory communityCounts,
            address[][] memory communityMembers
        ) = getRelevantCommunityInfo(msg.sender);

        bytes memory payload = abi.encode(
            msg.sender,
            hasToken[msg.sender],
            userInfo[msg.sender].tokenId,
            userInfo[msg.sender].isActive,
            userInfo[msg.sender].joinedCommunities,
            communities,
            communityCounts,
            communityMembers
        );

        for (uint i = 0; i < _dstChainIds.length; i++) {
            MessagingFee memory fee = _quote(_dstChainIds[i], payload, options, false);
            require(fee.nativeFee > 0 || fee.lzTokenFee > 0, "Invalid fee returned from _quote");
            totalFee.nativeFee += fee.nativeFee;
            totalFee.lzTokenFee += fee.lzTokenFee;
        }

        require(totalFee.nativeFee > 0 || totalFee.lzTokenFee > 0, "Total fee is zero");
        return totalFee;
    }

    // Function for existing NFT holders to join additional communities
    function joinAdditionalCommunity(address originalNFTContract) public onlyOwner {
        require(msg.sender != address(0), "Invalid address");
        require(originalNFTContract != address(0), "Invalid community address");
        require(hasToken[msg.sender], "User does not have an NFT");

        // Check if the user has already joined this community
        bool alreadyJoined = false;
        for (uint256 i = 0; i < userInfo[msg.sender].joinedCommunities.length; i++) {
            if (userInfo[msg.sender].joinedCommunities[i] == originalNFTContract) {
                alreadyJoined = true;
                break;
            }
        }
        require(!alreadyJoined, "User has already joined this community");

        // Add the new community
        userInfo[msg.sender].joinedCommunities.push(originalNFTContract);

        // Update community info
        communityInfo[originalNFTContract].communityMembers.push(msg.sender);
        communityInfo[originalNFTContract].communityCount++;

        emit AdditionalCommunityJoined(msg.sender, originalNFTContract, userInfo[msg.sender].tokenId);
    }

    // Events to emit when a user mints an NFT and joins their first community
    event NFTMintedAndCommunityJoined(address indexed user, address indexed community, uint256 tokenId);

    // Event to emit when an existing NFT holder joins an additional community
    event AdditionalCommunityJoined(address indexed user, address indexed community, uint256 tokenId);

    // Deactivate user's token
    function deactivate() public {
        // require(msg.sender == user || msg.sender == owner(), "Not authorized");
        require(userInfo[msg.sender].tokenId != 0, "User has no token");

        userInfo[msg.sender].isActive = false;
    }

    // Reactivate user's token
    function reactivate() public {
        require(userInfo[msg.sender].tokenId != 0, "User has no token");

        userInfo[msg.sender].isActive = true;
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
            address[] storage members = communityInfo[community].communityMembers;
            for (uint256 j = 0; j < members.length; j++) {
                if (members[j] == user) {
                    members[j] = members[members.length - 1];
                    members.pop();
                    communityInfo[community].communityCount--;
                    break;
                }
            }
        }

        delete userInfo[user];
        hasToken[user] = false;
    }

    // Get all members of a community
    function getCommunityMembers(address originalNFTContract) public view returns (address[] memory) {
        return communityInfo[originalNFTContract].communityMembers;
    }

    // Get user info, including joined communities
    function getUserInfo(address user) public view returns (UserInfo memory) {
        return userInfo[user];
    }

    // Get community count for a specific community
    function getCommunityCount(address originalNFTContract) public view returns (uint256) {
        return communityInfo[originalNFTContract].communityCount;
    }
}
