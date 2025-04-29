// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title NFTRoyaltyDistribution
 * @dev A simple NFT royalty distribution system for Core DAO
 */
contract NFTRoyaltyDistribution {
    // Events
    event RoyaltyReceived(uint256 indexed tokenId, uint256 amount);
    event RoyaltyDistributed(uint256 indexed tokenId, address recipient, uint256 amount);
    event CollaboratorAdded(uint256 indexed tokenId, address collaborator, uint256 sharePercentage);

    // State variables
    address public owner;
    
    // Mapping from tokenId to collaborators and their share percentages (in basis points, 100 = 1%)
    mapping(uint256 => mapping(address => uint256)) public royaltyShares;
    
    // Mapping from tokenId to total accumulated royalties not yet claimed
    mapping(uint256 => uint256) public pendingRoyalties;
    
    // Mapping from tokenId to array of collaborator addresses
    mapping(uint256 => address[]) public collaborators;

    // Constructor
    constructor() {
        owner = msg.sender;
    }

    /**
     * @dev Sets up collaborators and their shares for a specific NFT
     * @param tokenId The ID of the NFT
     * @param _collaborators Array of collaborator addresses
     * @param _shares Array of corresponding shares (in basis points, 100 = 1%)
     */
    function setupRoyaltyDistribution(
        uint256 tokenId,
        address[] memory _collaborators,
        uint256[] memory _shares
    ) external {
        require(msg.sender == owner, "Only owner can setup royalty distribution");
        require(_collaborators.length == _shares.length, "Arrays must have same length");
        
        uint256 totalShares = 0;
        
        // Clear previous collaborators if any
        address[] storage existingCollaborators = collaborators[tokenId];
        for (uint i = 0; i < existingCollaborators.length; i++) {
            royaltyShares[tokenId][existingCollaborators[i]] = 0;
        }
        
        // Reset collaborator array
        delete collaborators[tokenId];
        
        // Set new collaborators and shares
        for (uint i = 0; i < _collaborators.length; i++) {
            address collaborator = _collaborators[i];
            uint256 share = _shares[i];
            
            require(collaborator != address(0), "Invalid collaborator address");
            require(share > 0, "Share must be greater than 0");
            
            royaltyShares[tokenId][collaborator] = share;
            collaborators[tokenId].push(collaborator);
            totalShares += share;
            
            emit CollaboratorAdded(tokenId, collaborator, share);
        }
        
        // Ensure shares sum to 10000 (100%)
        require(totalShares == 10000, "Total shares must equal 10000 (100%)");
    }

    /**
     * @dev Receive royalty payment for a specific NFT
     * @param tokenId The ID of the NFT
     */
    function receiveRoyalty(uint256 tokenId) external payable {
        require(msg.value > 0, "Must send some ETH");
        require(collaborators[tokenId].length > 0, "No collaborators set up for this token");
        
        // Add to pending royalties
        pendingRoyalties[tokenId] += msg.value;
        
        emit RoyaltyReceived(tokenId, msg.value);
    }

    /**
     * @dev Distribute accumulated royalties to all collaborators for a specific NFT
     * @param tokenId The ID of the NFT
     */
    function distributeRoyalties(uint256 tokenId) external {
        uint256 amount = pendingRoyalties[tokenId];
        require(amount > 0, "No royalties to distribute");
        
        // Reset pending royalties before distribution to prevent reentrancy
        pendingRoyalties[tokenId] = 0;
        
        address[] storage tokenCollaborators = collaborators[tokenId];
        uint256 remainingAmount = amount;
        
        // Distribute to all collaborators except the last one
        for (uint i = 0; i < tokenCollaborators.length - 1; i++) {
            address collaborator = tokenCollaborators[i];
            uint256 share = royaltyShares[tokenId][collaborator];
            
            uint256 payment = (amount * share) / 10000;
            remainingAmount -= payment;
            
            (bool success, ) = collaborator.call{value: payment}("");
            require(success, "Transfer failed");
            
            emit RoyaltyDistributed(tokenId, collaborator, payment);
        }
        
        // Send remaining amount to the last collahttps://remix.ethereum.org/#borator to avoid dust
        if (tokenCollaborators.length > 0) {
            address lastCollaborator = tokenCollaborators[tokenCollaborators.length - 1];
            (bool success, ) = lastCollaborator.call{value: remainingAmount}("");
            require(success, "Transfer failed");
            
            emit RoyaltyDistributed(tokenId, lastCollaborator, remainingAmount);
        }
    }
}