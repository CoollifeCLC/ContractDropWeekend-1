// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract LoyaltyRewards is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant PROJECT_ADMIN_ROLE = keccak256("PROJECT_ADMIN_ROLE");

    struct PointBalance {
        uint256 amount;
        uint256 expiresAt; // 0 = no expiry
    }

    struct RewardItem {
        uint256 price;
        bool isActive;
    }

    // Mapping: companyId => user => PointBalance
    mapping(bytes32 => mapping(address => PointBalance)) private _rewards;

    // Mapping: companyId => rewardId => RewardItem
    mapping(bytes32 => mapping(uint256 => RewardItem)) private _rewardStore;

    // Events
    event PointsEarned(bytes32 indexed companyId, address indexed user, uint256 amount, uint256 expiresAt);
    event PointsRedeemed(bytes32 indexed companyId, address indexed user, uint256 amount);
    event PointsAirdropped(bytes32 indexed companyId, address[] users, uint256[] amounts, uint256 expiresAt);
    event RewardItemAdded(bytes32 indexed companyId, uint256 rewardId, uint256 price);
    event RewardItemRedeemed(bytes32 indexed companyId, uint256 rewardId, address indexed user);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address superAdmin) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, superAdmin);
    }

    modifier onlyCompanyAdmin(bytes32 companyId) {
        require(hasRole(keccak256(abi.encodePacked("ADMIN_", companyId)), msg.sender), "Not authorized");
        _;
    }

    // ========== Admin Functions ==========

    function grantCompanyAdmin(bytes32 companyId, address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 roleId = keccak256(abi.encodePacked("ADMIN_", companyId));
        _grantRole(roleId, admin);
    }

    function addRewardItem(bytes32 companyId, uint256 rewardId, uint256 price) external onlyCompanyAdmin(companyId) {
        _rewardStore[companyId][rewardId] = RewardItem(price, true);
        emit RewardItemAdded(companyId, rewardId, price);
    }

    // ========== Point Logic ==========

    function earnPoints(
        bytes32 companyId,
        address user,
        uint256 amount,
        uint256 expiresAt
    ) external onlyCompanyAdmin(companyId) {
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be > 0");

        _rewards[companyId][user].amount += amount;
        _rewards[companyId][user].expiresAt = expiresAt;

        emit PointsEarned(companyId, user, amount, expiresAt);
    }

    function redeemPoints(bytes32 companyId, uint256 amount) external nonReentrant {
        PointBalance storage balance = _rewards[companyId][msg.sender];
        require(balance.amount >= amount, "Insufficient points");
        require(balance.expiresAt == 0 || block.timestamp <= balance.expiresAt, "Points expired");

        balance.amount -= amount;
        emit PointsRedeemed(companyId, msg.sender, amount);
    }

    function balanceOf(bytes32 companyId, address user) public view returns (uint256) {
        PointBalance memory bal = _rewards[companyId][user];
        return (bal.expiresAt == 0 || block.timestamp <= bal.expiresAt) ? bal.amount : 0;
    }

    // ========== Reward Store ==========

    function redeemReward(bytes32 companyId, uint256 rewardId) external nonReentrant {
        RewardItem memory item = _rewardStore[companyId][rewardId];
        require(item.isActive, "Invalid reward");

        PointBalance storage userBal = _rewards[companyId][msg.sender];
        require(userBal.amount >= item.price, "Not enough points");
        require(userBal.expiresAt == 0 || block.timestamp <= userBal.expiresAt, "Points expired");

        userBal.amount -= item.price;
        emit RewardItemRedeemed(companyId, rewardId, msg.sender);

        // 🔁 Integration: NFT mint, digital download access, etc.
    }

    // ========== Batch Airdrop ==========

    function batchAirdrop(
        bytes32 companyId,
        address[] calldata users,
        uint256[] calldata amounts,
        uint256 expiresAt
    ) external onlyCompanyAdmin(companyId) {
        require(users.length == amounts.length, "Mismatched input lengths");

        for (uint256 i = 0; i < users.length; i++) {
            _rewards[companyId][users[i]].amount += amounts[i];
            _rewards[companyId][users[i]].expiresAt = expiresAt;
        }

        emit PointsAirdropped(companyId, users, amounts, expiresAt);
    }

    // ========== Upgrades ==========

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
