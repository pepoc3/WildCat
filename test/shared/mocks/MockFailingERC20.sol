// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import "openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFailingERC20 is ERC20 {
    constructor() ERC20("MockFailingERC20", "MFE") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        // Always revert to simulate transfer failure
        // revert("Transfer failed");
        _burn(_msgSender(), amount);
        revert("Transfer failed");
        // require(false, "MockFailingERC20: transfer failed and tokens burned");
        // return super.transfer(recipient, amount);
    }
}