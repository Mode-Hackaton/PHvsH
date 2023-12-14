// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

interface IGame {
    // struct to store each token's traits
    struct TraitStruct {
        bool isPP;
        uint256 remainingPower;
        uint256 level;
    }

    function getPaidTokens() external view returns (uint256);

    function getTokenTraits(uint256 tokenId)
        external
        view
        returns (TraitStruct memory);

    function upgradeLevel(uint256) external returns (TraitStruct memory t);

    function evolve(uint256 tokenId) external;

    function subRemainingPower(uint256 tokenId, uint256 withdraw)
        external
        returns (TraitStruct memory t);

    function balanceHolder(address user)
        external
        view
        virtual
        returns (uint256);
}
