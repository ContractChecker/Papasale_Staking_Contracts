// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IStakingPool {
    struct Stake {
        address user;
        uint256 id;
        uint256 amount;
        uint256 timestamp;
        bool    active;
    }

    struct PoolInfo {
        address token;
        address owner;
        uint256 bonus;
        uint256 lockDuration;
        uint256 emergencyWithdrawFee;
        uint256 liveStakedAmount;
        uint256 rewardDebt;
        uint256 tokensLeft;
        uint8   decimals;
        string[] strings;
        Stake[] stakes;

        Stake[] userStakes;
    }

    struct CardInfo {
        address pool;
        address token;
        uint256 bonus;
        uint256 lockDuration;
        uint256 liveStakedAmount;
        uint256 tokensLeft;
        uint256 stakeAmount;
        uint8   decimals;
        string[] strings;
    }

    struct Arguments {
        address[] addresses;
        string [] strings;
        uint256[] numbers;
    }

    function getPoolInfo (address user) external view returns (PoolInfo memory);
    function getCardInfo() external view returns (CardInfo memory);
    function initialize(address factory, address owner, Arguments memory arguments) external;
    function setBadges(uint256 _badgeID, string memory _link) external;
    function updateAllDetails(string[] memory details) external;
    function pause() external;
    function unpause() external;
}