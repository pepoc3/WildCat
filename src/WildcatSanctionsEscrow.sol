// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './interfaces/IERC20.sol';
import './interfaces/IWildcatSanctionsEscrow.sol';
import './interfaces/IWildcatSanctionsSentinel.sol';
import './libraries/LibERC20.sol';

contract WildcatSanctionsEscrow is IWildcatSanctionsEscrow {
  using LibERC20 for address;

  address public immutable override sentinel;
  address public immutable override borrower;
  address public immutable override account;
  address internal immutable asset;

  constructor() {
    // 1. 设置 sentinel 为调用者
    sentinel = msg.sender;
    // 2. 从 sentinel 获取 borrower 和 account 地址，以及资产地址
    (borrower, account, asset) = IWildcatSanctionsSentinel(sentinel).tmpEscrowParams();
  }

  function balance() public view override returns (uint256) {
    //  返回资产地址的余额
    return IERC20(asset).balanceOf(address(this));
  }

  function canReleaseEscrow() public view override returns (bool) {
    //  检查 account 是否在 Chainalysis 的制裁名单上
    return !IWildcatSanctionsSentinel(sentinel).isSanctioned(borrower, account);
  }

  function escrowedAsset() public view override returns (address, uint256) {
    return (asset, balance());
  }

  function releaseEscrow() public override {
    // 1. 检查是否可以释放 escrow
    if (!canReleaseEscrow()) revert CanNotReleaseEscrow();
    // 2. 获取余额

    uint256 amount = balance();
    // 3. 获取账户地址和资产地址
    address _account = account;
    address _asset = asset;
    // 4. 转移资产
    asset.safeTransfer(_account, amount);

    emit EscrowReleased(_account, _asset, amount);
  }
}
