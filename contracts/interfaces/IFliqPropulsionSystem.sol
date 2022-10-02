// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IFliqPropulsionSystem {
    event LogBridgeSet(address indexed token, address indexed bridge);
    event LogConvert(
        address indexed server,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 amountFliqOut
    );
    event FliqBurned(uint256 indexed amount);
    event BastionChanged(address indexed oldBastion, address indexed newBastion);
    event FliqFarmChanged(address indexed oldFarm, address indexed newFarm);

    function setFliqFarm(address _newFliqFarm) external;

    function bridgeFor(address token) external view returns (address bridge);

    function setBridge(address token, address bridge) external;

    function convert(address token0, address token1) external;

    function convertMultiple(address[] calldata token0, address[] calldata token1) external;
}
