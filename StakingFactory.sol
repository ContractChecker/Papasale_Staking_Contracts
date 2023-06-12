// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./IStakingPool.sol";
import "./IStakingFactory.sol";

contract StakingFactory is Ownable, IStakingFactory, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private _admins;
    EnumerableSet.AddressSet private _stakingPools;
    address public stakingPoolImplementation;
    address public feeAddress;
    uint256 public fee;

    mapping(address => address[]) public userStakedPools;
    mapping(address => address[]) public userCreatedPools;

    event StakingPoolCreated(address indexed stakingPool, address indexed token);

    constructor(
        address stakingPoolImplementation_,
        address feeAddress_,
        uint256 fee_
    ) {
        stakingPoolImplementation = stakingPoolImplementation_;
        feeAddress = feeAddress_;
        fee = fee_;
        _admins.add(msg.sender);
        _admins.add(feeAddress);
    }

    modifier onlyAdmin() {
        require(_admins.contains(msg.sender), "Only admin");
        _;
    }

    function addAdmin(address admin) external onlyOwner {
        _admins.add(admin);
    }

    function removeAdmin(address admin) external onlyOwner {
        _admins.remove(admin);
    }

    function getAdmins() external view returns (address[] memory) {
        return _admins.values();
    }

    function isAdmin(address admin) external view returns (bool) {
        return _admins.contains(admin);
    }

    function setStakingPoolImplementation(address stakingPoolImplementation_) external onlyOwner {
        stakingPoolImplementation = stakingPoolImplementation_;
    }

    function setFeeAddress(address feeAddress_) external onlyOwner {
        feeAddress = feeAddress_;
    }

    function setFee(uint256 fee_) external onlyOwner {
        fee = fee_;
    }

    function stakingPools() public view returns (address[] memory) {
        return _stakingPools.values();
    }

    function createStakingPool(
        IStakingPool.Arguments memory arguments
    ) external payable nonReentrant {
        require(msg.value == fee, "Invalid fee");
        payable(feeAddress).transfer(fee);
        
        address stakingPool = Clones.clone(stakingPoolImplementation);
        IStakingPool(stakingPool).initialize(
            address(this),
            msg.sender,
            arguments
        );
        _stakingPools.add(stakingPool);
        userCreatedPools[msg.sender].push(stakingPool);
        emit StakingPoolCreated(stakingPool, arguments.addresses[0]);
    }

    function addUserStakedPool(address user) external {
        require(_stakingPools.contains(msg.sender), "Invalid staking pool");
        for (uint256 i = 0; i < userStakedPools[user].length; i++) {
            if (userStakedPools[user][i] == msg.sender) {
                return;
            }
        }
        userStakedPools[user].push(msg.sender);
    }

    function removeUserStakedPool(address user) external {
        require(_stakingPools.contains(msg.sender), "Invalid staking pool");
        address[] storage stakedPools = userStakedPools[user];
        uint256 length = stakedPools.length;
        for (uint256 i = 0; i < length; i++) {
            if (stakedPools[i] == msg.sender) {
                stakedPools[i] = stakedPools[length - 1];
                stakedPools.pop();
                break;
            }
        }
    }

    function removeStakingPool(address stakingPool) external onlyOwner {
        _stakingPools.remove(stakingPool);
    }

    function getAllCards() external view returns (IStakingPool.CardInfo[] memory) {
        uint256 length = _stakingPools.length();
        IStakingPool.CardInfo[] memory cards = new IStakingPool.CardInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            cards[i] = IStakingPool(_stakingPools.at(i)).getCardInfo();
        }
        return cards;
    }

    function getUserStakedCards(address user) external view returns (IStakingPool.CardInfo[] memory) {
        address[] memory stakedPools = userStakedPools[user];
        uint256 length = stakedPools.length;
        IStakingPool.CardInfo[] memory cards = new IStakingPool.CardInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            cards[i] = IStakingPool(stakedPools[i]).getCardInfo();
        }
        return cards;
    }

    function getUserCreatedCards(address user) external view returns (IStakingPool.CardInfo[] memory) {
        address[] memory createdPools = userCreatedPools[user];
        uint256 length = createdPools.length;
        IStakingPool.CardInfo[] memory cards = new IStakingPool.CardInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            cards[i] = IStakingPool(createdPools[i]).getCardInfo();
        }
        return cards;
    }

    function setBadges(address stakingPool, uint256 badgeID, string memory link) external onlyAdmin {
        IStakingPool(stakingPool).setBadges(badgeID, link);
    }

    function updateAllDetails(address stakingPool, string[] memory strings) external onlyAdmin {
        IStakingPool(stakingPool).updateAllDetails(strings);
    }

    function pausePool(address stakingPool) external onlyAdmin {
        IStakingPool(stakingPool).pause();
    }

    function unpausePool(address stakingPool) external onlyAdmin {
        IStakingPool(stakingPool).unpause();
    }
}