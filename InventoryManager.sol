// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract InventoryManager is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    bytes32 public constant INVENTORY_MANAGER_ROLE = keccak256("INVENTORY_MANAGER_ROLE");

    struct InventoryItem {
        uint256 id;
        string name;
        string sku;
        uint256 quantity;
        string category;
        string location;
        string metadataURI; // IPFS or Arweave
        bool active;
    }

    uint256 private nextItemId;
    mapping(uint256 => InventoryItem) private inventory;

    event ItemAdded(uint256 indexed itemId, string name, uint256 quantity);
    event QuantityUpdated(uint256 indexed itemId, uint256 newQty);
    event ItemRemoved(uint256 indexed itemId);
    event LowStockWarning(uint256 indexed itemId, uint256 quantity);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(INVENTORY_MANAGER_ROLE, admin);

        nextItemId = 1;
    }

    modifier onlyManager() {
        require(hasRole(INVENTORY_MANAGER_ROLE, msg.sender), "Not inventory manager");
        _;
    }

    function addItem(
        string memory name,
        string memory sku,
        uint256 quantity,
        string memory category,
        string memory location,
        string memory metadataURI
    ) external onlyManager nonReentrant {
        uint256 itemId = nextItemId++;
        inventory[itemId] = InventoryItem({
            id: itemId,
            name: name,
            sku: sku,
            quantity: quantity,
            category: category,
            location: location,
            metadataURI: metadataURI,
            active: true
        });
        emit ItemAdded(itemId, name, quantity);
    }

    function updateQuantity(uint256 itemId, uint256 newQty) external onlyManager nonReentrant {
        require(inventory[itemId].active, "Item inactive or not found");
        inventory[itemId].quantity = newQty;
        emit QuantityUpdated(itemId, newQty);
        if (newQty < 10) {
            emit LowStockWarning(itemId, newQty); // Adjustable threshold
        }
    }

    function removeItem(uint256 itemId) external onlyManager nonReentrant {
        require(inventory[itemId].active, "Item already inactive");
        inventory[itemId].active = false;
        emit ItemRemoved(itemId);
    }

    function getItem(uint256 itemId) external view returns (InventoryItem memory) {
        return inventory[itemId];
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
