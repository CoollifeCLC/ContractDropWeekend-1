// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

contract EscrowMarketplace is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ARBITRATOR_ROLE = keccak256("ARBITRATOR_ROLE");

    struct Listing {
        address seller;
        address buyer;
        address token; // address(0) for ETH, else ERC20 token address
        uint256 price;
        bool isSold;
        bool isDisputed;
        bool isConfirmed;
        string metadataURI; // IPFS or other URI
    }

    uint256 public listingCounter;
    mapping(uint256 => Listing) public listings;

    event ListingCreated(uint256 indexed id, address indexed seller, uint256 price, address token, string metadataURI);
    event ItemPurchased(uint256 indexed id, address indexed buyer);
    event DeliveryConfirmed(uint256 indexed id);
    event Disputed(uint256 indexed id);
    event DisputeResolved(uint256 indexed id, bool releasedToSeller);

    function initialize(address admin, address arbitrator) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(ARBITRATOR_ROLE, arbitrator);
    }

    function createListing(
        uint256 price,
        address token,
        string calldata metadataURI
    ) external returns (uint256) {
        require(price > 0, "Price must be > 0");

        listings[listingCounter] = Listing({
            seller: msg.sender,
            buyer: address(0),
            token: token,
            price: price,
            isSold: false,
            isDisputed: false,
            isConfirmed: false,
            metadataURI: metadataURI
        });

        emit ListingCreated(listingCounter, msg.sender, price, token, metadataURI);
        return listingCounter++;
    }

    function buyItem(uint256 id) external payable nonReentrant {
        Listing storage listing = listings[id];
        require(!listing.isSold, "Already sold");

        listing.buyer = msg.sender;
        listing.isSold = true;

        if (listing.token == address(0)) {
            require(msg.value == listing.price, "Incorrect ETH amount");
        } else {
            require(
                IERC20Upgradeable(listing.token).transferFrom(msg.sender, address(this), listing.price),
                "ERC20 transfer failed"
            );
        }

        emit ItemPurchased(id, msg.sender);
    }

    function confirmDelivery(uint256 id) external nonReentrant {
        Listing storage listing = listings[id];
        require(msg.sender == listing.buyer, "Only buyer");
        require(listing.isSold && !listing.isDisputed && !listing.isConfirmed, "Invalid state");

        listing.isConfirmed = true;

        _releaseFunds(listing, listing.seller);
        emit DeliveryConfirmed(id);
    }

    function dispute(uint256 id) external {
        Listing storage listing = listings[id];
        require(msg.sender == listing.buyer || msg.sender == listing.seller, "Not authorized");
        require(listing.isSold && !listing.isConfirmed, "Cannot dispute");

        listing.isDisputed = true;
        emit Disputed(id);
    }

    function resolveDispute(uint256 id, bool releaseToSeller) external onlyRole(ARBITRATOR_ROLE) nonReentrant {
        Listing storage listing = listings[id];
        require(listing.isDisputed, "No dispute");

        listing.isDisputed = false;
        listing.isConfirmed = true;

        address recipient = releaseToSeller ? listing.seller : listing.buyer;
        _releaseFunds(listing, recipient);

        emit DisputeResolved(id, releaseToSeller);
    }

    function _releaseFunds(Listing storage listing, address recipient) internal {
        if (listing.token == address(0)) {
            (bool sent, ) = recipient.call{value: listing.price}("");
            require(sent, "ETH payment failed");
        } else {
            require(
                IERC20Upgradeable(listing.token).transfer(recipient, listing.price),
                "ERC20 payment failed"
            );
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
