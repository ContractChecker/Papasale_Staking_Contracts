// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IStakingPool.sol";
import "./IStakingFactory.sol";

contract StakingPool is IStakingPool, Initializable, ReentrancyGuard, Pausable {
    using EnumerableSet for EnumerableSet.AddressSet;

    IERC20Metadata public token;
    address public owner;
    uint256 public bonus; // Divided by 10000
    uint256 public lockDuration;
    uint256 public emergencyWithdrawFee; // Divided by 100

    uint256 public liveStakedAmount;

    string[] public strings; 
    // 0: Logo URL, 1: Description, 2: Video, 3: Banner URL 
    // Gap for future use
    // 10: Website,  11: Facebook,  12: Twitter, 13: Github, 
    // 14: Telegram, 15: Instagram, 16: Discord, 17: Reddit,
    // Gap for future use
    // 20: Audit, 21: KYC
    // Gap for future use
    // 25: Token Name, 26: Token Symbol

    IStakingFactory public factory;

    Stake[] public stakes;
    mapping(address => Stake[]) public userStakes;

    event Staked(address indexed user, uint256 amount);

    function initialize(address factory_, address owner_, Arguments memory arguments) external initializer {
        owner = owner_;
        factory = IStakingFactory(factory_);

        token = IERC20Metadata(arguments.addresses[0]);

        bonus = arguments.numbers[0];
        lockDuration = arguments.numbers[1];
        emergencyWithdrawFee = arguments.numbers[2];
        require(bonus > 0, "Bonus must be greater than 0");
        require(lockDuration > 0, "Lock duration must be greater than 0");
        require(emergencyWithdrawFee <= 50, "Emergency withdraw cannot be greater than 50%");

        strings = arguments.strings;

        strings[25] = token.name();
        strings[26] = token.symbol();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "Only factory");
        _;
    }

    modifier onlyFactoryOrOwner() {
        require(msg.sender == address(factory) || msg.sender == owner, "Only factory or owner");
        _;
    }

    function pause() external onlyFactory {
        _pause();
    }

    function unpause() external onlyFactory {
        _unpause();
    }

    function updateAllDetails(string[] memory details) external onlyFactoryOrOwner {
        require(details.length == 20, "Invalid details length");
        for (uint256 i = 0; i < details.length; i++) {
            strings[i] = details[i];
        }
    }

    function setBadges(uint256 _badgeID, string memory _link) external onlyFactory {
        strings[_badgeID] = _link;
    }

    function addUserStakedPool(address user) private {
        factory.addUserStakedPool(user);
    }

    function removeUserStakedPool(address user) private {
        for (uint256 i = 0; i < userStakes[user].length; i++) {
            if (userStakes[user][i].active) {
                return;
            }
        }
        factory.removeUserStakedPool(user);
    }

    function withdrawExcessToken() external onlyOwner nonReentrant {
        uint256 tokensLeft = getTokensLeft();
        uint256 balanceBefore = token.balanceOf(address(this));
        token.transfer(owner, tokensLeft);
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter == balanceBefore - tokensLeft, "Pool is not excluded from fee");
    }

    function getRewardDebt() public view returns (uint256) {
        uint256 rewardDebt = liveStakedAmount * bonus / 10000;
        return rewardDebt;
    }

    function getTokensLeft() public view returns (uint256) {
        uint256 rewardDebt = getRewardDebt();
        uint256 balance = token.balanceOf(address(this));
        uint256 tokensLeft = balance - liveStakedAmount - rewardDebt;
        return tokensLeft;
    }

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(getTokensLeft() >= amount * bonus / 10000, "Insufficient tokens left in the pool for rewards");
        uint256 balanceBefore = token.balanceOf(address(this));
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter == balanceBefore + amount, "Pool is not excluded from fee");

        liveStakedAmount += amount;
        Stake memory S = Stake(msg.sender, stakes.length, amount, block.timestamp, true);
        stakes.push(S);
        userStakes[msg.sender].push(S);
        addUserStakedPool(msg.sender);
        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 stakeID) external nonReentrant whenNotPaused {
        require(stakeID < stakes.length, "Invalid stake ID");
        Stake memory S = stakes[stakeID];
        require(S.user == msg.sender, "You are not the owner of this stake");
        require(S.active, "Stake is not active");
        require(block.timestamp >= S.timestamp + lockDuration, "Stake is still locked");
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 _bonus = S.amount * bonus / 10000;
        require(token.transfer(S.user, S.amount + _bonus), "Transfer failed");
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter == balanceBefore - (S.amount + _bonus), "Pool is not excluded from fee");

        liveStakedAmount -= S.amount;
        S.active = false;
        stakes[stakeID] = S;
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            if (userStakes[msg.sender][i].id == stakeID) {
                userStakes[msg.sender][i] = S;
                break;
            }
        }
        removeUserStakedPool(msg.sender);
    }

    function emergencyWithdraw(uint256 stakeID) external nonReentrant whenNotPaused {
        require(stakeID < stakes.length, "Invalid stake ID");
        Stake memory S = stakes[stakeID];
        require(S.user == msg.sender, "You are not the owner of this stake");
        require(S.active, "Stake is not active");
        uint256 balanceBefore = token.balanceOf(address(this));
        uint256 _emergencyWithdrawFee = S.amount * emergencyWithdrawFee / 100;
        require(token.transfer(S.user, S.amount - _emergencyWithdrawFee), "Transfer failed");
        require(token.transfer(owner, _emergencyWithdrawFee), "Transfer failed");
        uint256 balanceAfter = token.balanceOf(address(this));
        require(balanceAfter == balanceBefore - S.amount, "Pool is not excluded from fee");

        liveStakedAmount -= S.amount;
        S.active = false;
        stakes[stakeID] = S;
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            if (userStakes[msg.sender][i].id == stakeID) {
                userStakes[msg.sender][i] = S;
                break;
            }
        }
        removeUserStakedPool(msg.sender);
    }

    function getPoolInfo (address user) external view returns (PoolInfo memory) {
        PoolInfo memory poolInfo = PoolInfo(
            address(token),
            owner,
            bonus,
            lockDuration,
            emergencyWithdrawFee,
            liveStakedAmount,
            getRewardDebt(),
            getTokensLeft(),
            token.decimals(),
            strings,
            stakes,
            userStakes[user]
        );
        return poolInfo;
    }

    function getCardInfo () external view returns (CardInfo memory) {
        CardInfo memory cardInfo = CardInfo(
            address(this),
            address(token),
            bonus,
            lockDuration,
            liveStakedAmount,
            getTokensLeft(),
            stakes.length,
            token.decimals(),
            strings
        );
        return cardInfo;
    }
}