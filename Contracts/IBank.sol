// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

// import "./Battle.sol";

interface IBank {
    function counterByWallet(address user) external view returns (uint256);
}
