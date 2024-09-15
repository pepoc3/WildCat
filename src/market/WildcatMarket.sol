// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './WildcatMarketBase.sol';
import './WildcatMarketConfig.sol';
import './WildcatMarketToken.sol';
import './WildcatMarketWithdrawals.sol';
import '../WildcatSanctionsSentinel.sol';

contract WildcatMarket is
  WildcatMarketBase,
  WildcatMarketConfig,
  WildcatMarketToken,
  WildcatMarketWithdrawals
{
  using MathUtils for uint256;
  using SafeCastLib for uint256;
  using LibERC20 for address;
  using BoolUtils for bool;

  /**
   * @dev Apply pending interest, delinquency fees and protocol fees
   *      to the state and process the pending withdrawal batch if
   *      one exists and has expired, then update the market's
   *      delinquency status.
   */
  function updateState() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();
    _writeState(state);
  }

  /**
   * @dev Token rescue function for recovering tokens sent to the market
   *      contract by mistake or otherwise outside of the normal course of
   *      operation.
   */
  function rescueTokens(address token) external onlyBorrower {
    if ((token == asset).or(token == address(this))) {
      revert_BadRescueAsset();
    }
    token.safeTransferAll(msg.sender);
  }

  /**
   * @dev Deposit up to `amount` underlying assets and mint market tokens
   *      for `msg.sender`.
   *
   *      The actual deposit amount is limited by the market's maximum deposit
   *      amount, which is the configured `maxTotalSupply` minus the current
   *      total supply.
   *
   *      Reverts if the market is closed or if the scaled token amount
   *      that would be minted for the deposit is zero.
   */
  function _depositUpTo(
    uint256 amount
  ) internal virtual nonReentrant returns (uint256 /* actualAmount */) {
    // Get current state
    MarketState memory state = _getUpdatedState();

    if (state.isClosed) revert_DepositToClosedMarket();

    // Reduce amount if it would exceed totalSupply
    amount = MathUtils.min(amount, state.maximumDeposit());

    // Scale the mint amount
    uint104 scaledAmount = state.scaleAmount(amount).toUint104();
    if (scaledAmount == 0) revert_NullMintAmount();

    // Cache account data and revert if not authorized to deposit.
    Account memory account = _getAccount(msg.sender);

    hooks.onDeposit(msg.sender, scaledAmount, state);

    // Transfer deposit from caller
    asset.safeTransferFrom(msg.sender, address(this), amount);

    account.scaledBalance += scaledAmount;
    _accounts[msg.sender] = account;

    emit_Transfer(_runtimeConstant(address(0)), msg.sender, amount);
    emit_Deposit(msg.sender, amount, scaledAmount);

    // Increase supply
    state.scaledTotalSupply += scaledAmount;

    // Update stored state
    _writeState(state);

    return amount;
  }

  /**
   * @dev Deposit up to `amount` underlying assets and mint market tokens
   *      for `msg.sender`.
   *
   *      The actual deposit amount is limited by the market's maximum deposit
   *      amount, which is the configured `maxTotalSupply` minus the current
   *      total supply.
   *
   *      Reverts if the market is closed or if the scaled token amount
   *      that would be minted for the deposit is zero.
   */
  function depositUpTo(
    uint256 amount
  ) external virtual sphereXGuardExternal returns (uint256 /* actualAmount */) {
    return _depositUpTo(amount);
  }

  /**
   * @dev Deposit exactly `amount` underlying assets and mint market tokens
   *      for `msg.sender`.
   *
   *     Reverts if the deposit amount would cause the market to exceed the
   *     configured `maxTotalSupply`.
   */
  function deposit(uint256 amount) external virtual sphereXGuardExternal {
    uint256 actualAmount = _depositUpTo(amount);
    if (amount != actualAmount) revert_MaxSupplyExceeded();
  }

  /**
   * @dev Withdraw available protocol fees to the fee recipient.
   */
  function collectFees() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState(); // 获取当前的市场状态
    if (state.accruedProtocolFees == 0) revert_NullFeeAmount(); // 如果累计的协议费用为0，则抛出错误

    uint128 withdrawableFees = state.withdrawableProtocolFees(totalAssets()); // 计算可提取的协议费用
    if (withdrawableFees == 0) revert_InsufficientReservesForFeeWithdrawal(); // 如果可提取的协议费用为0，则抛出错误

    state.accruedProtocolFees -= withdrawableFees; // 更新累计的协议费用
    asset.safeTransfer(feeRecipient, withdrawableFees); // 将协议费用转移到feeRecipient
    _writeState(state); // 更新市场状态
    emit_FeesCollected(withdrawableFees); // 触发FeesCollected事件
  }

  /**
   * // 从市场提取资金到借款人。
   * @dev Withdraw funds from the market to the borrower.
   * // 只能提取未用于满足借款人抵押义务的资产。
   *      Can only withdraw up to the assets that are not required
   *      to meet the borrower's collateral obligations.
   * // 如果市场已关闭，则抛出错误。
   *      Reverts if the market is closed.
   */
  function borrow(uint256 amount) external onlyBorrower nonReentrant sphereXGuardExternal {
    // 检查借款人是否在Chainalysis上被标记为受制裁实体。
    // 使用 `isFlaggedByChainalysis` 而不是 `isSanctioned` 以防止借款人覆盖其制裁状态。
    // Check if the borrower is flagged as a sanctioned entity on Chainalysis.
    // Uses `isFlaggedByChainalysis` instead of `isSanctioned` to prevent the borrower
    // overriding their sanction status.
    if (_isFlaggedByChainalysis(borrower)) { //检查借款人是否在Chainalysis上被标记为受制裁实体。
      revert_BorrowWhileSanctioned(); //如果借款人被标记为受制裁实体，则抛出错误。
    }

    MarketState memory state = _getUpdatedState(); // 获取当前的市场状态
    if (state.isClosed) revert_BorrowFromClosedMarket(); // 如果市场已关闭，则抛出错误

    uint256 borrowable = state.borrowableAssets(totalAssets());// 计算可借用的资产数量
    if (amount > borrowable) revert_BorrowAmountTooHigh();// 如果借款金额大于可借用的资产数量，则抛出错误

    // 执行借款钩子（如果启用）
    // Execute borrow hook if enabled        
    hooks.onBorrow(amount, state);

    asset.safeTransfer(msg.sender, amount); // 将借款金额转移到借款人
    _writeState(state); // 更新市场状态
    emit_Borrow(amount); // 触发Borrow事件
  }

  // 还款
  function _repay(MarketState memory state, uint256 amount, uint256 baseCalldataSize) internal {
    if (amount == 0) revert_NullRepayAmount(); // 如果还款金额为0，则抛出错误
    if (state.isClosed) revert_RepayToClosedMarket(); // 如果市场已关闭，则抛出错误

    asset.safeTransferFrom(msg.sender, address(this), amount);// 将还款金额从借款人转移到市场
    emit_DebtRepaid(msg.sender, amount); //  触发DebtRepaid事件

    // Execute repay hook if enabled // 执行还款钩子（如果启用）
    hooks.onRepay(amount, state, baseCalldataSize);
  }

  // 借款人还款未偿还的债务
  function repayOutstandingDebt() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState(); // 获取当前的市场状态
    // 如果总债务大于总资产，那么差额就是未偿还的债务。
    // 如果总债务小于或等于总资产，那么未偿还的债务就是0（因为使用了饱和减法）。
    uint256 outstandingDebt = state.totalDebts().satSub(totalAssets()); // 计算未偿还的债务
    _repay(state, outstandingDebt, 0x04); // 还款
    _writeState(state);
  }

  //偿还市场中的逾期债务
  function repayDelinquentDebt() external nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState();// 获取当前的市场状态
    uint256 delinquentDebt = state.liquidityRequired().satSub(totalAssets());// 计算逾期债务
    _repay(state, delinquentDebt, 0x04);// 还款
    _writeState(state);// 更新市场状态  
  }

  /**
   * @dev Transfers funds from the caller to the market.
   *
   *      Any payments made through this function are considered
   *      repayments from the borrower. Do *not* use this function
   *      if you are a lender or an unrelated third party.
   *
   *      Reverts if the market is closed or `amount` is 0.
   */
    /**
   * @dev 将资金从调用者转移到市场。
   *
   *      通过此函数进行的任何付款都被视为借款人的还款。
   *      如果你是贷款人或无关的第三方，请*不要*使用此函数。
   *
   *      如果市场已关闭或`amount`为0，则会回滚交易。
   */
  function repay(uint256 amount) external nonReentrant sphereXGuardExternal {
    if (amount == 0) revert_NullRepayAmount();// 如果还款金额为0，则抛出错误

    asset.safeTransferFrom(msg.sender, address(this), amount);// 将还款金额从调用者转移到市场
    emit_DebtRepaid(msg.sender, amount);// 触发DebtRepaid事件

    MarketState memory state = _getUpdatedState();// 获取当前的市场状态
    if (state.isClosed) revert_RepayToClosedMarket();// 如果市场已关闭，则抛出错误

    // Execute repay hook if enabled
    hooks.onRepay(amount, state, _runtimeConstant(0x24));// 执行还款钩子（如果启用）

    _writeState(state);// 更新市场状态
  }

  /**
   * @dev Sets the market APR to 0% and marks market as closed.
   *
   *      Can not be called if there are any unpaid withdrawal batches.
   *
   *      Transfers remaining debts from borrower if market is not fully
   *      collateralized; otherwise, transfers any assets in excess of
   *      debts to the borrower.
   */
     /**
    * @dev 将市场年利率（APR）设置为0%并标记市场为已关闭。
    *
    *      如果存在任何未支付的提款批次，则无法调用此函数。
    *
    *      如果市场未完全抵押，则从借款人处转移剩余债务；
    *      否则，将超出债务的任何资产转移给借款人。
    * 
    * 借款人承担了市场的主要风险。如果市场表现不佳，借款人可能需要补足差额。
    * 因此，当市场表现良好时，多余的资产归还给他们是对这种风险的补偿。
    */
  function closeMarket() external onlyBorrower nonReentrant sphereXGuardExternal {
    MarketState memory state = _getUpdatedState(); // 获取当前的市场状态

    if (state.isClosed) revert_MarketAlreadyClosed(); // 如果市场已关闭，则抛出错误

    uint256 currentlyHeld = totalAssets(); // 计算当前持有的资产
    uint256 totalDebts = state.totalDebts(); // 计算总债务
    if (currentlyHeld < totalDebts) { // 如果当前持有的资产小于总债务
      // Transfer remaining debts from borrower 从借款人处转移剩余的债务
      uint256 remainingDebt = totalDebts - currentlyHeld;// 计算剩余的债务
      _repay(state, remainingDebt, 0x04);// 还款
      currentlyHeld += remainingDebt;// 更新当前持有的资产
    } else if (currentlyHeld > totalDebts) { // 如果当前持有的资产大于总债务
      uint256 excessDebt = currentlyHeld - totalDebts;//市场多余的资产
      // Transfer excess assets to borrower
      asset.safeTransfer(borrower, excessDebt);// 将多余的资产归还给借款人
      currentlyHeld -= excessDebt;// 更新当前持有的资产
    }
    hooks.onCloseMarket(state);// 执行关闭市场钩子
    state.annualInterestBips = 0;// 将市场年利率设置为0%
    state.isClosed = true;// 标记市场为已关闭 
    //当市场关闭时，将储备金率设置为 100% 意味着所有剩余资产都被视为储备金。
    // 这是为了确保所有剩余资金都可用于偿还债务和处理提款。
    state.reserveRatioBips = 10000;// 将市场储备金比例设置为100%
    // 确保逾期费用不会进一步增加规模因子
    // as doing so would mean last lender in market couldn't fully redeem
    state.timeDelinquent = 0;// 将市场逾期时间设置为0
    // 仍跟踪可用流动性以防舍入错误
    // Still track available liquidity in case of a rounding error
    //@audit state.normalizedUnclaimedWithdrawals和state.accruedProtocolFees感觉有问题
    uint256 availableLiquidity = currentlyHeld -
      (state.normalizedUnclaimedWithdrawals + state.accruedProtocolFees);// 计算可用流动性
    // 如果存在未完全支付的提款批次，则为此批次设置最多可用的流动性
    // If there is a pending withdrawal batch which is not fully paid off, set aside
    // up to the available liquidity for that batch.
    if (state.pendingWithdrawalExpiry != 0) { // 如果存在未完全支付的提款批次
      uint32 expiry = state.pendingWithdrawalExpiry; // 获取提款批次的到期时间
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry]; // 获取提款批次
      if (batch.scaledAmountBurned < batch.scaledTotalAmount) { // 如果提款批次未完全支付
        (, uint128 normalizedAmountPaid) = _applyWithdrawalBatchPayment( // 应用提款批次支付
          batch, // 提款批次
          state, // 市场状态
          expiry, // 提款批次的到期时间
          availableLiquidity // 可用流动性
        );
        availableLiquidity -= normalizedAmountPaid; // 更新可用流动性
        _withdrawalData.batches[expiry] = batch; // 更新提款批次
      }
    }

    uint256 numBatches = _withdrawalData.unpaidBatches.length(); // 获取未支付的提款批次数量
    for (uint256 i; i < numBatches; i++) { // 遍历未支付的提款批次
      // 使用可用流动性处理下一个未支付的批次
      // Process the next unpaid batch using available liquidity
      uint256 normalizedAmountPaid = _processUnpaidWithdrawalBatch(state, availableLiquidity); // 处理未支付的提款批次
      // 减少可用流动性以供下一个批次使用
      // Reduce liquidity available to next batch
      availableLiquidity -= normalizedAmountPaid; // 更新可用流动性
    }

    if (state.scaledPendingWithdrawals != 0) { // 如果存在未支付的提款批次
      revert_CloseMarketWithUnpaidWithdrawals();  // 如果存在未支付的提款批次，则抛出错误
    }

    _writeState(state); // 更新市场状态
    emit_MarketClosed(block.timestamp); // 触发MarketClosed事件
  }

  /**
   * // 阻止一个受制裁账户的全部提款
   * @dev Queues a full withdrawal of a sanctioned account's assets.
   */
  function _blockAccount(MarketState memory state, address accountAddress) internal override {
    Account memory account = _accounts[accountAddress]; // 获取账户
    if (account.scaledBalance > 0) { // 如果账户的缩放余额大于0
      uint104 scaledAmount = account.scaledBalance; // 获取缩放余额

      uint256 normalizedAmount = state.normalizeAmount(scaledAmount); // 将缩放余额转换为标准化余额

      uint32 expiry = _queueWithdrawal( // 将提款批次添加到队列中
        state, // 市场状态
        account, // 账户
        accountAddress, // 账户地址
        scaledAmount, // 缩放余额
        normalizedAmount, // 标准化余额
        msg.data.length // 数据长度
      );

      emit_SanctionedAccountAssetsQueuedForWithdrawal( // 触发SanctionedAccountAssetsQueuedForWithdrawal事件  
        accountAddress, // 账户地址
        expiry, // 到期时间
        scaledAmount, // 缩放余额
        normalizedAmount // 标准化余额
      );
    }
  }
}
