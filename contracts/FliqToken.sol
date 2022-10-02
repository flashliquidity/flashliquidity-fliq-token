// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

contract FliqToken is ERC20Votes {
    constructor(address recipient) ERC20("FlashLiquidity", "FLIQ") ERC20Permit("FlashLiquidity") {
        _mint(recipient, 1e26); // 100kk (1e8 * 1e18)
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    // The functions below are overrides required by Solidity.
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20Votes) {
        super._burn(account, amount);
    }
}
