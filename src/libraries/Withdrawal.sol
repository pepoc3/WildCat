// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './MarketState.sol';
import './FIFOQueue.sol';

using MathUtils for uint256;
using WithdrawalLib for WithdrawalBatch global;

/**
 *    
 * Withdrawals are grouped together in batches with a fixed expiry.
 * Until a withdrawal is paid out, the tokens are not burned from the market
 * and continue to accumulate interest.
 *
 * 提款批次：    //@audit 提款批次是为贷款人（即存款人）设计的
 *     提款批次是具有固定到期时间的提款集合。
 *     在提款未支付之前，代币不会被燃烧，并且会继续积累利息。
 */
struct WithdrawalBatch {
  // Total scaled amount of tokens to be withdrawn
  // 提款批次中代币的总缩放数量   要提款的代币总量，按比例缩放。
  uint104 scaledTotalAmount;
  // Amount of scaled tokens that have been paid by borrower
  // 要提款的代币总量，按比例缩放。   scaledAmount：缩放后的代币数量
  uint104 scaledAmountBurned;
  // Amount of normalized tokens that have been paid by borrower
  // 已由借款人支付的标准化代币数量。  normalizedAmount：标准化后的代币数量
  uint128 normalizedAmountPaid;
}

struct AccountWithdrawalStatus {
  uint104 scaledAmount;  // 缩放后的代币数量
  uint128 normalizedAmountWithdrawn;  // 标准化后的代币数量
}

struct WithdrawalData {
  FIFOQueue unpaidBatches;  // 未支付的提款批次
  mapping(uint32 => WithdrawalBatch) batches;  // 提款批次
  mapping(uint256 => mapping(address => AccountWithdrawalStatus)) accountStatuses;  // 账户提款状态
}

library WithdrawalLib {
  function scaledOwedAmount(WithdrawalBatch memory batch) internal pure returns (uint104) {
    return batch.scaledTotalAmount - batch.scaledAmountBurned;
  }

  /**    
   * @dev Get the amount of assets which are not already reserved
   *      for prior withdrawal batches. This must only be used on
   *      the latest withdrawal batch to expire.    
   * @dev 获取未用于先前提款批次的资产数量。这只能在最新的提款批次到期时使用。
   */
  function availableLiquidityForPendingBatch(
    WithdrawalBatch memory batch,  // 提款批次
    MarketState memory state,  // 市场状态
    uint256 totalAssets  // 总资产
  ) internal pure returns (uint256) {
    // Subtract normalized value of pending scaled withdrawals, processed
    // withdrawals and protocol fees.
    
    uint256 priorScaledAmountPending = (state.scaledPendingWithdrawals - batch.scaledOwedAmount());
    //计算在处理提款批次时不可用的资产数量
    uint256 unavailableAssets = state.normalizedUnclaimedWithdrawals +
      state.normalizeAmount(priorScaledAmountPending) +
      state.accruedProtocolFees;
    // 返回总资产减去不可用资产的数量 得出可用的资产
    return totalAssets.satSub(unavailableAssets);
  }
}
