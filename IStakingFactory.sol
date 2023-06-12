// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

interface IStakingFactory {
    function addUserStakedPool(address user) external;
    function removeUserStakedPool(address user) external;
}