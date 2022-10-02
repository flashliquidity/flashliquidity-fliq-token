// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IFlashLiquidityPair} from "./interfaces/IFlashLiquidityPair.sol";
import {IFlashLiquidityFactory} from "./interfaces/IFlashLiquidityFactory.sol";
import {IFlashLiquidityBastion} from "./interfaces/IFlashLiquidityBastion.sol";
import {IFliqPropulsionSystem} from "./interfaces/IFliqPropulsionSystem.sol";
import {BastionConnector, IERC20, SafeERC20} from "./types/BastionConnector.sol";
import {FliqToken} from "./FliqToken.sol";

contract FliqPropulsionSystem is IFliqPropulsionSystem, BastionConnector {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public fliqFarm;
    address public immutable factory;
    address public immutable fliq;
    address public immutable dai;

    mapping(address => address) internal _bridges;

    constructor(
        address _governor,
        address _factory,
        address _fliq,
        address _dai,
        uint256 _transferGovernanceDelay
    ) BastionConnector(_governor, _transferGovernanceDelay) {
        factory = _factory;
        fliq = _fliq;
        dai = _dai;
    }

    function initialize(address _bastion) external onlyGovernor {
        initializeConnector(_bastion);
    }

    function setFliqFarm(address _newFliqFarm) external override onlyGovernor {
        address _oldFliqFarm = fliqFarm;
        fliqFarm = _newFliqFarm;
        emit FliqFarmChanged(_oldFliqFarm, _newFliqFarm);
    }

    function bridgeFor(address token) public view override returns (address bridge) {
        bridge = _bridges[token];
        if (bridge == address(0)) {
            bridge = dai;
        }
    }

    function setBridge(address token, address bridge) external override onlyGovernor {
        // Checks
        require(token != fliq && token != dai && token != bridge, "Invalid bridge");

        // Effects
        _bridges[token] = bridge;
        emit LogBridgeSet(token, bridge);
    }

    function convert(address token0, address token1) external override onlyGovernor {
        _convert(token0, token1);
        _burnFLIQ();
    }

    function convertMultiple(address[] calldata token0, address[] calldata token1)
        external
        override
        onlyGovernor
    {
        // TODO: This can be optimized a fair bit, but this is safer and simpler for now
        uint256 len = token0.length;
        for (uint256 i = 0; i < len; i++) {
            _convert(token0[i], token1[i]);
        }
        _burnFLIQ();
    }

    function _convert(address token0, address token1) internal {
        IFlashLiquidityPair pair = IFlashLiquidityPair(
            IFlashLiquidityFactory(factory).getPair(token0, token1)
        );
        require(address(pair) != address(0), "Invalid pair");
        IERC20(address(pair)).safeTransfer(address(pair), pair.balanceOf(address(this)));
        (uint256 amount0, uint256 amount1) = pair.burn(address(this));
        if (token0 != pair.token0()) {
            (amount0, amount1) = (amount1, amount0);
        }

        uint256 _fliqOut = _convertStep(token0, token1, amount0, amount1);

        emit LogConvert(msg.sender, token0, token1, amount0, amount1, _fliqOut);
    }

    function _convertStep(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 fliqOut) {
        // Interactions
        if (token0 == token1) {
            uint256 amount = amount0.add(amount1);
            if (token0 == fliq) {
                _toFliqFarm(amount);
                fliqOut = amount;
            } else if (token0 == dai) {
                fliqOut = _toFLIQ(dai, amount);
            } else {
                address bridge = bridgeFor(token0);
                amount = _swap(token0, bridge, amount, address(this));
                fliqOut = _convertStep(bridge, bridge, amount, 0);
            }
        } else if (token0 == fliq) {
            // eg. SUSHI - ETH
            _toFliqFarm(amount0);
            fliqOut = _toFLIQ(token1, amount1).add(amount0);
        } else if (token1 == fliq) {
            // eg. USDT - SUSHI
            _toFliqFarm(amount1);
            fliqOut = _toFLIQ(token0, amount0).add(amount1);
        } else if (token0 == dai) {
            // eg. ETH - USDC
            fliqOut = _toFLIQ(dai, _swap(token1, dai, amount1, address(this)).add(amount0));
        } else if (token1 == dai) {
            // eg. USDT - ETH
            fliqOut = _toFLIQ(dai, _swap(token0, dai, amount0, address(this)).add(amount1));
        } else {
            // eg. MIC - USDT
            address bridge0 = bridgeFor(token0);
            address bridge1 = bridgeFor(token1);
            if (bridge0 == token1) {
                // eg. MIC - USDT - and bridgeFor(MIC) = USDT
                fliqOut = _convertStep(
                    bridge0,
                    token1,
                    _swap(token0, bridge0, amount0, address(this)),
                    amount1
                );
            } else if (bridge1 == token0) {
                // eg. WBTC - DSD - and bridgeFor(DSD) = WBTC
                fliqOut = _convertStep(
                    token0,
                    bridge1,
                    amount0,
                    _swap(token1, bridge1, amount1, address(this))
                );
            } else {
                fliqOut = _convertStep(
                    bridge0,
                    bridge1, // eg. USDT - DSD - and bridgeFor(DSD) = WBTC
                    _swap(token0, bridge0, amount0, address(this)),
                    _swap(token1, bridge1, amount1, address(this))
                );
            }
        }
    }

    function _swap(
        address fromToken,
        address toToken,
        uint256 amountIn,
        address to
    ) internal returns (uint256 amountOut) {
        IFlashLiquidityPair pair = IFlashLiquidityPair(
            IFlashLiquidityFactory(factory).getPair(fromToken, toToken)
        );
        require(address(pair) != address(0), "Cannot convert");

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountInWithFee = amountIn.mul(997);
        address _flashbot = pair.flashbot();
        if (_flashbot != address(0)) {
            IFlashLiquidityBastion(bastion).setFlashbot(address(pair), address(this));
        }
        if (fromToken == pair.token0()) {
            amountOut = amountInWithFee.mul(reserve1) / reserve0.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(0, amountOut, to, new bytes(0));
            // TODO: Add maximum slippage?
        } else {
            amountOut = amountInWithFee.mul(reserve0) / reserve1.mul(1000).add(amountInWithFee);
            IERC20(fromToken).safeTransfer(address(pair), amountIn);
            pair.swap(amountOut, 0, to, new bytes(0));
            // TODO: Add maximum slippage?
        }

        if (_flashbot != address(0)) {
            IFlashLiquidityBastion(bastion).setFlashbot(address(pair), _flashbot);
        }
    }

    function _toFLIQ(address token, uint256 amountIn) internal returns (uint256 amountOut) {
        amountOut = _swap(token, fliq, amountIn, address(this));
    }

    function _toFliqFarm(uint256 amount) internal {
        address _fliqFarm = fliqFarm;
        if (_fliqFarm != address(0)) {
            IERC20(fliq).safeTransfer(_fliqFarm, amount);
        }
    }

    function _burnFLIQ() internal {
        uint256 fliqBalance = FliqToken(fliq).balanceOf(address(this));
        if (fliqBalance > 0) {
            FliqToken(fliq).burn(fliqBalance);
            emit FliqBurned(fliqBalance);
        }
    }
}
