// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import '../ReentrancyGuard.sol';
import '../spherex/SphereXProtectedRegisteredBase.sol';
import '../interfaces/IMarketEventsAndErrors.sol';
import '../interfaces/IERC20.sol';
import '../IHooksFactory.sol';
import '../libraries/FeeMath.sol';
import '../libraries/MarketErrors.sol';
import '../libraries/MarketEvents.sol';
import '../libraries/Withdrawal.sol';
import '../libraries/FunctionTypeCasts.sol';
import '../libraries/LibERC20.sol';
import '../types/HooksConfig.sol';

contract WildcatMarketBase is
  SphereXProtectedRegisteredBase,
  ReentrancyGuard,
  IMarketEventsAndErrors
{
  using SafeCastLib for uint256;
  using MathUtils for uint256;
  using FunctionTypeCasts for *;
  using LibERC20 for address;

  // ==================================================================== //
  //                       Market Config (immutable)                       //
  // ==================================================================== //

  /**
   * @dev Return the contract version string "2".
   */
  function version() external pure returns (string memory) {
    assembly {
      mstore(0x40, 0)
      mstore(0x41, 0x0132)
      mstore(0x20, 0x20)
      return(0x20, 0x60)
    }
  }

  HooksConfig public immutable hooks;

  /// @dev Account with blacklist control, used for blocking sanctioned addresses.
  address public immutable sentinel;

  /// @dev Account with authority to borrow assets from the market.
  address public immutable borrower;

  /// @dev Factory that deployed the market. Has the ability to update the protocol fee.
  address public immutable factory;

  /// @dev Account that receives protocol fees.
  address public immutable feeRecipient;

  /// @dev Penalty fee added to interest earned by lenders, does not affect protocol fee.
  uint public immutable delinquencyFeeBips;

  /// @dev Time after which delinquency incurs penalty fee.
  uint public immutable delinquencyGracePeriod;

  /// @dev Time before withdrawal batches are processed.
  uint public immutable withdrawalBatchDuration;

  /// @dev Token decimals (same as underlying asset).
  uint8 public immutable decimals;

  /// @dev Address of the underlying asset.
  address public immutable asset;

  bytes32 internal immutable PACKED_NAME_WORD_0;
  bytes32 internal immutable PACKED_NAME_WORD_1;
  bytes32 internal immutable PACKED_SYMBOL_WORD_0;
  bytes32 internal immutable PACKED_SYMBOL_WORD_1;

  function symbol() external view returns (string memory) {
    bytes32 symbolWord0 = PACKED_SYMBOL_WORD_0;
    bytes32 symbolWord1 = PACKED_SYMBOL_WORD_1;

    assembly {
      // The layout here is:
      // 0x00: Offset to the string
      // 0x20: Length of the string
      // 0x40: First word of the string
      // 0x60: Second word of the string
      // The first word of the string that is kept in immutable storage also contains the
      // length byte, meaning the total size limit of the string is 63 bytes.
      mstore(0, 0x20)
      mstore(0x20, 0)
      mstore(0x3f, symbolWord0)
      mstore(0x5f, symbolWord1)
      return(0, 0x80)
    }
  }

  function name() external view returns (string memory) {
    bytes32 nameWord0 = PACKED_NAME_WORD_0;
    bytes32 nameWord1 = PACKED_NAME_WORD_1;

    assembly {
      // The layout here is:
      // 0x00: Offset to the string
      // 0x20: Length of the string
      // 0x40: First word of the string
      // 0x60: Second word of the string
      // The first word of the string that is kept in immutable storage also contains the
      // length byte, meaning the total size limit of the string is 63 bytes.
      mstore(0, 0x20)
      mstore(0x20, 0)
      mstore(0x3f, nameWord0)
      mstore(0x5f, nameWord1)
      return(0, 0x80)
    }
  }

  /// @dev Returns immutable arch-controller address.
  function archController() external view returns (address) {
    return _archController;
  }

  // ===================================================================== //
  //                             Market State                               //
  // ===================================================================== //

  MarketState internal _state;

  mapping(address => Account) internal _accounts;

  WithdrawalData internal _withdrawalData;

  // ===================================================================== //
  //                             Constructor                               //
  // ===================================================================== //

  function _getMarketParameters() internal view returns (uint256 marketParametersPointer) {
    assembly {
      marketParametersPointer := mload(0x40)
      mstore(0x40, add(marketParametersPointer, 0x260))
      // Write the selector for IHooksFactory.getMarketParameters
      mstore(0x00, 0x04032dbb)
      // Call `getMarketParameters` and copy the returned struct to the allocated memory
      // buffer, reverting if the call fails or does not return the correct amount of bytes.
      // This overrides all the ABI decoding safety checks, as the call is always made to
      // the factory contract which will only ever return the prepared market parameters.
      if iszero(
        and(
          eq(returndatasize(), 0x260),
          staticcall(gas(), caller(), 0x1c, 0x04, marketParametersPointer, 0x260)
        )
      ) {
        revert(0, 0)
      }
    }
  }

  constructor() {
    factory = msg.sender;
    // Cast the function signature of `_getMarketParameters` to get a valid reference to
    // a `MarketParameters` object without creating a duplicate allocation or unnecessarily
    // zeroing out the memory buffer.
    MarketParameters memory parameters = _getMarketParameters.asReturnsMarketParameters()();

    // Set asset metadata
    asset = parameters.asset;
    decimals = parameters.decimals;

    PACKED_NAME_WORD_0 = parameters.packedNameWord0;
    PACKED_NAME_WORD_1 = parameters.packedNameWord1;
    PACKED_SYMBOL_WORD_0 = parameters.packedSymbolWord0;
    PACKED_SYMBOL_WORD_1 = parameters.packedSymbolWord1;

    {
      // Initialize the market state - all values in slots 1 and 2 of the struct are
      // initialized to zero, so they are skipped.

      uint maxTotalSupply = parameters.maxTotalSupply;
      uint reserveRatioBips = parameters.reserveRatioBips;
      uint annualInterestBips = parameters.annualInterestBips;
      uint protocolFeeBips = parameters.protocolFeeBips;

      assembly {
        // MarketState Slot 0 Storage Layout:
        // [15:31] | state.maxTotalSupply
        // [31:32] | state.isClosed = false

        let slot0 := shl(8, maxTotalSupply)
        sstore(_state.slot, slot0)

        // MarketState Slot 3 Storage Layout:
        // [4:8] | lastInterestAccruedTimestamp
        // [8:22] | scaleFactor = 1e27
        // [22:24] | reserveRatioBips
        // [24:26] | annualInterestBips
        // [26:28] | protocolFeeBips
        // [28:32] | timeDelinquent = 0

        let slot3 := or(
          or(or(shl(0xc0, timestamp()), shl(0x50, RAY)), shl(0x40, reserveRatioBips)),
          or(shl(0x30, annualInterestBips), shl(0x20, protocolFeeBips))
        )

        sstore(add(_state.slot, 3), slot3)
      }
    }

    hooks = parameters.hooks;
    sentinel = parameters.sentinel;
    borrower = parameters.borrower;
    feeRecipient = parameters.feeRecipient;
    delinquencyFeeBips = parameters.delinquencyFeeBips;
    delinquencyGracePeriod = parameters.delinquencyGracePeriod;
    withdrawalBatchDuration = parameters.withdrawalBatchDuration;
    _archController = parameters.archController;
    __SphereXProtectedRegisteredBase_init(parameters.sphereXEngine);
  }

  // ===================================================================== //
  //                              Modifiers                                //
  // ===================================================================== //

  modifier onlyBorrower() {
    address _borrower = borrower;
    assembly {
      // Equivalent to
      // if (msg.sender != borrower) revert NotApprovedBorrower();
      if xor(caller(), _borrower) {
        mstore(0, 0x02171e6a)
        revert(0x1c, 0x04)
      }
    }
    _;
  }

  // ===================================================================== //
  //                       Internal State Getters                          //
  // ===================================================================== //

  /**
   * @dev Retrieve an account from storage.
   *
   *      Reverts if account is sanctioned.
   */
  function _getAccount(address accountAddress) internal view returns (Account memory account) {
    account = _accounts[accountAddress]; // 获取账户数据
    // 如果账户被制裁，则抛出AccountBlocked错误
    if (_isSanctioned(accountAddress)) revert_AccountBlocked();
  }

  /**
   * @dev Checks if `account` is flagged as a sanctioned entity by Chainalysis.
   *      If an account is flagged mistakenly, the borrower can override their
   *      status on the sentinel and allow them to interact with the market.
   */
  /**
 * @dev 检查 `account` 是否被 Chainalysis 标记为受制裁实体。
 *      如果一个账户被错误地标记，借款人可以在哨兵（sentinel）上
 *      覆盖他们的状态，并允许他们与市场进行交互。
 */
  function _isSanctioned(address account) internal view returns (bool result) {
    address _borrower = borrower; // 获取借款人地址
    address _sentinel = address(sentinel); // 获取哨兵地址
    assembly {
      let freeMemoryPointer := mload(0x40) // 获取自由内存指针
      mstore(0, 0x06e74444) // 存储函数选择器
      mstore(0x20, _borrower) // 存储借款人地址
      mstore(0x40, account) // 存储账户地址
      // 调用 `sentinel.isSanctioned(borrower, account)` ，
      //如果调用失败或不返回32字节，则抛出错误。
      // Call `sentinel.isSanctioned(borrower, account)` and revert if the call fails
      // or does not return 32 bytes.
      if iszero(
        // 检查返回的数据大小是否为32字节，并且调用是否成功
        and(eq(returndatasize(), 0x20), staticcall(gas(), _sentinel, 0x1c, 0x44, 0, 0x20))
      ) {
        returndatacopy(0, 0, returndatasize()) // 复制返回的数据
        revert(0, returndatasize()) // 抛出错误
      }
      // 读取返回结果
      result := mload(0)  
      // 将自由内存指针存储回0x40
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ===================================================================== //
  //                       External State Getters                          //
  // ===================================================================== //

  /**
   * @dev Returns the amount of underlying assets the borrower is obligated
   *      to maintain in the market to avoid delinquency.
   */
  function coverageLiquidity() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().liquidityRequired();
  }

  /**
   * @dev Returns the scale factor (in ray) used to convert scaled balances
   *      to normalized balances.
   */
  function scaleFactor() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaleFactor;
  }

  /**
   * @dev Total balance in underlying asset.
   */
  function totalAssets() public view returns (uint256) {
    return asset.balanceOf(address(this));
  }

  /**
   * @dev Returns the amount of underlying assets the borrower is allowed
   *      to borrow.
   *
   *      This is the balance of underlying assets minus:
   *      - pending (unpaid) withdrawals
   *      - paid withdrawals
   *      - reserve ratio times the portion of the supply not pending withdrawal
   *      - protocol fees
   */
  function borrowableAssets() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().borrowableAssets(totalAssets());
  }

  /**
   * @dev Returns the amount of protocol fees (in underlying asset amount)
   *      that have accrued and are pending withdrawal.
   */
  function accruedProtocolFees() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().accruedProtocolFees;
  }

  function totalDebts() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().totalDebts();
  }

  /**
   * @dev Returns the state of the market as of the last update.
   */
  function previousState() external view returns (MarketState memory) {
    MarketState memory state = _state;

    assembly {
      return(state, 0x1c0)
    }
  }

  /**
   * @dev Return the state the market would have at the current block after applying
   *      interest and fees accrued since the last update and processing the pending
   *      withdrawal batch if it is expired.
   */
  function currentState() external view nonReentrantView returns (MarketState memory state) {
    state = _calculateCurrentStatePointers.asReturnsMarketState()();
    assembly {
      return(state, 0x1c0)
    }
  }

  /**
   * @dev Call `_calculateCurrentState()` and return only the `state` parameter.
   *
   *      Casting the function type prevents a duplicate declaration of the MarketState
   *      return parameter, which would cause unnecessary zeroing and allocation of memory.
   *      With `viaIR` enabled, the cast is a noop.
   */
  function _calculateCurrentStatePointers() internal view returns (uint256 state) {
    (state, , ) = _calculateCurrentState.asReturnsPointers()();
  }

  /**
   * @dev Returns the scaled total supply the vaut would have at the current block
   *      after applying interest and fees accrued since the last update and burning
   *      market tokens for the pending withdrawal batch if it is expired.
   */
  function scaledTotalSupply() external view nonReentrantView returns (uint256) {
    return _calculateCurrentStatePointers.asReturnsMarketState()().scaledTotalSupply;
  }

  /**
   * @dev Returns the scaled balance of `account`
   */
  function scaledBalanceOf(address account) external view nonReentrantView returns (uint256) {
    return _accounts[account].scaledBalance;
  }

  /**
   * @dev Returns the amount of protocol fees that are currently
   *      withdrawable by the fee recipient.
   */
  function withdrawableProtocolFees() external view returns (uint128) {
    return
      _calculateCurrentStatePointers.asReturnsMarketState()().withdrawableProtocolFees(
        totalAssets()
      );  // 返回当前可提取的协议费用
  }

  // /*//////////////////////////////////////////////////////////////
  //                     Internal State Handlers
  // //////////////////////////////////////////////////////////////*/

  function _blockAccount(MarketState memory state, address accountAddress) internal virtual {}

  /**
   * @dev Returns cached MarketState after accruing interest and delinquency / protocol fees
   *      and processing expired withdrawal batch, if any.
   *      返回当前的市场状态，并更新利息和滞纳金/协议费用，并处理过期的提款批次，如果有的话。
   *      Used by functions that make additional changes to `state`.
   *      方法用于在修改状态后进行额外的更改。
   *      NOTE: Returned `state` does not match `_state` if interest is accrued
   *            Calling function must update `_state` or revert.
   *      注意：如果计算了利息，返回的`state`与`_state`不匹配，调用函数必须更新`_state`或抛出错误。
   * @return state Market state after interest is accrued.
   */
  function _getUpdatedState() internal returns (MarketState memory state) {
    state = _state; // 获取当前的市场状态
    // Handle expired withdrawal batch 处理过期的提款批次
    if (state.hasPendingExpiredBatch()) { // 如果存在过期的提款批次
      uint256 expiry = state.pendingWithdrawalExpiry; // 获取过期提款批次的到期时间
      // Only accrue interest if time has passed since last update.
      // 只有在自上次更新以来时间已过时，才计算利息。
      // This will only be false if withdrawalBatchDuration is 0.
      // 这只有在withdrawalBatchDuration为0时才会为false。
      uint32 lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp; // 获取上次利息计算的时间戳
      if (expiry != lastInterestAccruedTimestamp) { // 如果过期提款批次的到期时间不等于上次利息计算的时间戳
        (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee) = state // 计算利息和滞纳金以及协议费用
          .updateScaleFactorAndFees( // 更新比例因子并计算费用
            delinquencyFeeBips, // 滞纳金费率
            delinquencyGracePeriod, // 滞纳期
            expiry // 过期提款批次的到期时间
          );
        emit_InterestAndFeesAccrued( // 触发InterestAndFeesAccrued事件
          lastInterestAccruedTimestamp,
          expiry,
          state.scaleFactor,
          baseInterestRay,
          delinquencyFeeRay,
          protocolFee
        );
      }
      _processExpiredWithdrawalBatch(state); // 处理过期的提款批次
    }
    uint32 lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp; // 获取上次利息计算的时间戳
    // 如果当前时间戳不等于上次利息计算的时间戳，则计算利息和滞纳金以及协议费用
    // Apply interest and fees accrued since last update (expiry or previous tx)
    if (block.timestamp != lastInterestAccruedTimestamp) {
      (uint256 baseInterestRay, uint256 delinquencyFeeRay, uint256 protocolFee) = state  // 计算利息和滞纳金以及协议费用
        .updateScaleFactorAndFees(
          delinquencyFeeBips, // 滞纳金费率
          delinquencyGracePeriod, // 滞纳期
          block.timestamp // 当前时间戳
        );
      emit_InterestAndFeesAccrued(
        lastInterestAccruedTimestamp,
        block.timestamp,
        state.scaleFactor,
        baseInterestRay,
        delinquencyFeeRay,
        protocolFee
      );
    }
  
    // 如果有待处理的提款批次尚未完全付清，则留出该批次的可用流动资金。
    // If there is a pending withdrawal batch which is not fully paid off, set aside    
    // up to the available liquidity for that batch.
    if (state.pendingWithdrawalExpiry != 0) { // 如果有一个挂起的提款请求需要处理
      uint32 expiry = state.pendingWithdrawalExpiry; // 获取提款批次的到期时间
      WithdrawalBatch memory batch = _withdrawalData.batches[expiry]; // 获取提款批次
      if (batch.scaledAmountBurned < batch.scaledTotalAmount) { // 如果批次未完全支付
        // 用可用流动性尽可能多地燃烧批次
        // Burn as much of the withdrawal batch as possible with available liquidity.
        uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(state, totalAssets()); // 计算可用流动性
        if (availableLiquidity > 0) { // 如果可用流动性大于0
          _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity); // 应用提款批次支付
          _withdrawalData.batches[expiry] = batch; // 更新过期提款批次
        }
      }
    }
  }

  /**
   * @dev Calculate the current state, applying fees and interest accrued since
   *      the last state update as well as the effects of withdrawal batch expiry
   *      on the market state.
   *      Identical to _getUpdatedState() except it does not modify storage or
   *      or emit events.
   *      Returns expired batch data, if any, so queries against batches have
   *      access to the most recent data.
   */
  function _calculateCurrentState()
    internal
    view
    returns (
      MarketState memory state,
      uint32 pendingBatchExpiry,
      WithdrawalBatch memory pendingBatch
    )
  {
    state = _state;
    // Handle expired withdrawal batch
    if (state.hasPendingExpiredBatch()) {
      pendingBatchExpiry = state.pendingWithdrawalExpiry;
      // Only accrue interest if time has passed since last update.
      // This will only be false if withdrawalBatchDuration is 0.
      if (pendingBatchExpiry != state.lastInterestAccruedTimestamp) {
        state.updateScaleFactorAndFees(
          delinquencyFeeBips,
          delinquencyGracePeriod,
          pendingBatchExpiry
        );
      }

      pendingBatch = _withdrawalData.batches[pendingBatchExpiry];
      uint256 availableLiquidity = pendingBatch.availableLiquidityForPendingBatch(
        state,
        totalAssets()
      );
      if (availableLiquidity > 0) {
        _applyWithdrawalBatchPaymentView(pendingBatch, state, availableLiquidity);
      }
      state.pendingWithdrawalExpiry = 0;
    }

    if (state.lastInterestAccruedTimestamp != block.timestamp) {
      state.updateScaleFactorAndFees(
        delinquencyFeeBips,
        delinquencyGracePeriod,
        block.timestamp
      );
    }

    // If there is a pending withdrawal batch which is not fully paid off, set aside
    // up to the available liquidity for that batch.
    if (state.pendingWithdrawalExpiry != 0) {
      pendingBatchExpiry = state.pendingWithdrawalExpiry;
      pendingBatch = _withdrawalData.batches[pendingBatchExpiry];
      if (pendingBatch.scaledAmountBurned < pendingBatch.scaledTotalAmount) {
        // Burn as much of the withdrawal batch as possible with available liquidity.
        uint256 availableLiquidity = pendingBatch.availableLiquidityForPendingBatch(
          state,
          totalAssets()
        );
        if (availableLiquidity > 0) {
          _applyWithdrawalBatchPaymentView(pendingBatch, state, availableLiquidity);
        }
      }
    }
  }

  /** // 将缓存的市场状态写入存储并触发事件
   * @dev Writes the cached MarketState to storage and emits an event.
   * // 在所有修改 `state` 的函数结束时使用
   *      Used at the end of all functions which modify `state`.
   * 
   */
  function _writeState(MarketState memory state) internal {
    bool isDelinquent = state.liquidityRequired() > totalAssets();// 检查市场是否处于违约状态 
    state.isDelinquent = isDelinquent; // 更新市场状态

    {
      bool isClosed = state.isClosed; // 检查市场是否已关闭
      uint maxTotalSupply = state.maxTotalSupply; // 获取最大总供应量
      assembly {
        //  槽位0的存储布局：
        // Slot 0 Storage Layout:
        // [15:31] | state.maxTotalSupply
        // [31:32] | state.isClosed
        //由于 isClosed 是一个布尔值（1 字节），它会占用存储槽的第 0-7 位（低位）。
        //左移后的 maxTotalSupply 占用存储槽的第 8-255 位（高位）。
        let slot0 := or(isClosed, shl(0x08, maxTotalSupply)) // 将市场状态存储在槽位0中
        sstore(_state.slot, slot0) // 将槽位0存储在状态中
      }
    }
    {
      uint accruedProtocolFees = state.accruedProtocolFees; // 获取累计的协议费用
      uint normalizedUnclaimedWithdrawals = state.normalizedUnclaimedWithdrawals; // 获取未领取的提款数量
      assembly {
        // 槽位1的存储布局：
        // Slot 1 Storage Layout:
        // [0:16] | state.normalizedUnclaimedWithdrawals
        // [16:32] | state.accruedProtocolFees
        let slot1 := or(accruedProtocolFees, shl(0x80, normalizedUnclaimedWithdrawals)) // 将累计的协议费用和未领取的提款数量存储在槽位1中
        sstore(add(_state.slot, 1), slot1) // 将槽位1存储在状态中
      }
    }
    {
      uint scaledTotalSupply = state.scaledTotalSupply; // 获取缩放的总供应量 
      uint scaledPendingWithdrawals = state.scaledPendingWithdrawals; // 获取待支付的缩放提款数量
      uint pendingWithdrawalExpiry = state.pendingWithdrawalExpiry; // 获取待支付的提款到期时间
      assembly {
        // Slot 2 Storage Layout:
        // [1:2] | state.isDelinquent
        // [2:6] | state.pendingWithdrawalExpiry
        // [6:19] | state.scaledPendingWithdrawals
        // [19:32] | state.scaledTotalSupply
        let slot2 := or(
          or(
            or(shl(0xf0, isDelinquent), shl(0xd0, pendingWithdrawalExpiry)),
            shl(0x68, scaledPendingWithdrawals)
          ),
          scaledTotalSupply
        )
        sstore(add(_state.slot, 2), slot2) // 将槽位2存储在状态中
      }
    }
    {
      uint timeDelinquent = state.timeDelinquent; // 获取违约时间
      uint protocolFeeBips = state.protocolFeeBips; // 获取协议费率
      uint annualInterestBips = state.annualInterestBips; // 获取年利率
      uint reserveRatioBips = state.reserveRatioBips; // 获取储备金率
      uint scaleFactor = state.scaleFactor; // 获取比例因子
      uint lastInterestAccruedTimestamp = state.lastInterestAccruedTimestamp; // 获取上次利息计算的时间戳
      assembly {
        // Slot 3 Storage Layout:
        // [4:8] | state.lastInterestAccruedTimestamp
        // [8:22] | state.scaleFactor
        // [22:24] | state.reserveRatioBips
        // [24:26] | state.annualInterestBips
        // [26:28] | protocolFeeBips
        // [28:32] | state.timeDelinquent
        let slot3 := or(
          or(
            or(
              or(shl(0xc0, lastInterestAccruedTimestamp), shl(0x50, scaleFactor)),
              shl(0x40, reserveRatioBips)
            ),
            or(
              shl(0x30, annualInterestBips),
              shl(0x20, protocolFeeBips)
            )
          ),
          timeDelinquent
        )
        sstore(add(_state.slot, 3), slot3)
      }
    }
    emit_StateUpdated(state.scaleFactor, isDelinquent);
  }

  /**   处理过期的提款批次:
   *     提取可用的资产来支付批次
   *     如果可用资产足以支付批次，则关闭批次并保留总提款金额。
   *     如果可用资产不足以支付批次，则记录批次为未支付批次，并保留可用资产。
   *     保留给批次的资产按当前比例因子缩放，并燃烧相应数量的缩放代币，确保借款人不会继续支付已提款资产的利息。 
   * @dev Handles an expired withdrawal batch:
   *      - Retrieves the amount of underlying assets that can be used to pay for the batch.
   *      - If the amount is sufficient to pay the full amount owed to the batch, the batch
   *        is closed and the total withdrawal amount is reserved.
   *      - If the amount is insufficient to pay the full amount owed to the batch, the batch
   *        is recorded as an unpaid batch and the available assets are reserved.
   *      - The assets reserved for the batch are scaled by the current scale factor and that
   *        amount of scaled tokens is burned, ensuring borrowers do not continue paying interest
   *        on withdrawn assets.
   * 提款批次是将多个提款请求组合在一起，并为这些请求设置一个固定的到期时间。
   * 如果在到期时间之前，
   * 这些提款请求未能被处理或支付，那么这些批次就被视为过期的提款批次
   *        
   */
  function _processExpiredWithdrawalBatch(MarketState memory state) internal {
    uint32 expiry = state.pendingWithdrawalExpiry; // 获取过期提款批次的到期时间
    WithdrawalBatch memory batch = _withdrawalData.batches[expiry]; // 获取过期提款批次

    if (batch.scaledAmountBurned < batch.scaledTotalAmount) {  // 如果批次未完全支付  
      // Burn as much of the withdrawal batch as possible with available liquidity.
      // 用可用流动性尽可能多地燃烧批次
      uint256 availableLiquidity = batch.availableLiquidityForPendingBatch(state, totalAssets()); // 计算可用流动性
      if (availableLiquidity > 0) {
        _applyWithdrawalBatchPayment(batch, state, expiry, availableLiquidity); // 应用提款批次支付
      }
    }

    emit_WithdrawalBatchExpired(
      expiry,
      batch.scaledTotalAmount,
      batch.scaledAmountBurned,
      batch.normalizedAmountPaid
    );

    if (batch.scaledAmountBurned < batch.scaledTotalAmount) {
      _withdrawalData.unpaidBatches.push(expiry);
    } else {
      emit_WithdrawalBatchClosed(expiry);
    }

    state.pendingWithdrawalExpiry = 0;

    _withdrawalData.batches[expiry] = batch;
  }

  /**
   * @dev Process withdrawal payment, burning market tokens and reserving
   *      underlying assets so they are only available for withdrawals.
   * @dev 处理提款支付时，燃烧市场代币并保留基础资产，以确保这些资产仅用于满足提款请求
   */
//   缩放的数量用于内部计算: 缩放的数量通常用于内部计算，以确保高精度和一致性。例如，在计算利息、费用或其他金融操作时，使用缩放的数量可以避免精度损失。
// 标准化的数量用于外部交互: 标准化的数量通常用于外部交互，例如与用户或其他合约进行交互时。标准化的数量可以简化计算过程，并确保在不同场景中的可比性。
  function _applyWithdrawalBatchPayment(
    WithdrawalBatch memory batch,  // 提款批次  
    MarketState memory state,  // 市场状态
    uint32 expiry,  // 到期时间
    uint256 availableLiquidity
  ) internal returns (uint104 scaledAmountBurned, uint128 normalizedAmountPaid) { //@audit 为什么始终有缩放的数量和标准化的数量
    
    // 计算未支付的缩放代币数量
    uint104 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;

    // Do nothing if batch is already paid
    // 如果批次已支付，则返回0
    if (scaledAmountOwed == 0) return (0, 0);
    // 缩放可用流动性
    uint256 scaledAvailableLiquidity = state.scaleAmount(availableLiquidity);
    // 计算燃烧的缩放代币数量
    // 这行代码的目的是计算实际燃烧的缩放代币数量，
    // 取当前可用的缩放流动性和尚未支付的缩放代币数量中的最小值。
    // 这样可以确保不会燃烧超过可用流动性的代币数量。
    scaledAmountBurned = MathUtils.min(scaledAvailableLiquidity, scaledAmountOwed).toUint104();
    // Use mulDiv instead of normalizeAmount to round `normalizedAmountPaid` down, ensuring
    // it is always possible to finish withdrawal batches on closed markets.
    // 使用 mulDiv 而不是 normalizeAmount 来向下舍入 `normalizedAmountPaid`，
    // 确保在关闭的市场中始终可以完成提款批次。
    //@audit 准备测试这句话
    normalizedAmountPaid = MathUtils.mulDiv(scaledAmountBurned, state.scaleFactor, RAY).toUint128();

    batch.scaledAmountBurned += scaledAmountBurned; // 更新批次已燃烧的缩放代币数量
    batch.normalizedAmountPaid += normalizedAmountPaid; // 更新批次已支付的标准化数量
    state.scaledPendingWithdrawals -= scaledAmountBurned; // 更新市场待支付的缩放代币数量

    // Update normalizedUnclaimedWithdrawals so the tokens are only accessible for withdrawals.
    // 更新 normalizedUnclaimedWithdrawals 以确保代币仅可用于提款。
    state.normalizedUnclaimedWithdrawals += normalizedAmountPaid;

    // Burn market tokens to stop interest accrual upon withdrawal payment.
    // 燃烧市场代币以停止提款支付后的利息累积。
    state.scaledTotalSupply -= scaledAmountBurned;

    // Emit transfer for external trackers to indicate burn.
    // 为外部跟踪器发出转移，以指示燃烧。 
    emit_Transfer(address(this), _runtimeConstant(address(0)), normalizedAmountPaid);
    emit_WithdrawalBatchPayment(expiry, scaledAmountBurned, normalizedAmountPaid);
  }

  function _applyWithdrawalBatchPaymentView(
    WithdrawalBatch memory batch,
    MarketState memory state,
    uint256 availableLiquidity
  ) internal pure {
    uint104 scaledAmountOwed = batch.scaledTotalAmount - batch.scaledAmountBurned;
    // Do nothing if batch is already paid
    if (scaledAmountOwed == 0) return;

    uint256 scaledAvailableLiquidity = state.scaleAmount(availableLiquidity);
    uint104 scaledAmountBurned = MathUtils
      .min(scaledAvailableLiquidity, scaledAmountOwed)
      .toUint104();
    // Use mulDiv instead of normalizeAmount to round `normalizedAmountPaid` down, ensuring
    // it is always possible to finish withdrawal batches on closed markets.
    uint128 normalizedAmountPaid = MathUtils
      .mulDiv(scaledAmountBurned, state.scaleFactor, RAY)
      .toUint128();

    batch.scaledAmountBurned += scaledAmountBurned;
    batch.normalizedAmountPaid += normalizedAmountPaid;
    state.scaledPendingWithdrawals -= scaledAmountBurned;

    // Update normalizedUnclaimedWithdrawals so the tokens are only accessible for withdrawals.
    state.normalizedUnclaimedWithdrawals += normalizedAmountPaid;

    // Burn market tokens to stop interest accrual upon withdrawal payment.
    state.scaledTotalSupply -= scaledAmountBurned;
  }

  /**
   * @dev Function to obfuscate the fact that a value is constant from solc's optimizer.
   *      This prevents function specialization for calls with a constant input parameter,
   *      which usually has very little benefit in terms of gas savings but can
   *      drastically increase contract size.
   *
   *      The value returned will always match the input value outside of the constructor,
   *      fallback and receive functions.
   */
  function _runtimeConstant(
    uint256 actualConstant
  ) internal pure returns (uint256 runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }

  function _runtimeConstant(
    address actualConstant
  ) internal pure returns (address runtimeConstant) {
    assembly {
      mstore(0, actualConstant)
      runtimeConstant := mload(iszero(calldatasize()))
    }
  }

  function _isFlaggedByChainalysis(address account) internal view returns (bool isFlagged) {
    address sentinelAddress = address(sentinel); // 获取哨兵地址
    assembly {
      mstore(0, 0x95c09839) // 调用 sentinelAddress 的 0x95c09839 函数
      mstore(0x20, account) // 将 account 地址存储在内存中
      if iszero(
        and(eq(returndatasize(), 0x20), staticcall(gas(), sentinelAddress, 0x1c, 0x24, 0, 0x20)) // 调用 sentinelAddress 的 0x95c09839 函数
      ) {
        returndatacopy(0, 0, returndatasize()) // 将 returndatasize() 复制到内存中
        revert(0, returndatasize()) // 抛出错误
      }
      isFlagged := mload(0) // 将 mload(0) 存储到 isFlagged 变量中
    }
  }

  function _createEscrowForUnderlyingAsset(
    address accountAddress
  ) internal returns (address escrow) {
    address tokenAddress = address(asset);
    address borrowerAddress = borrower;
    address sentinelAddress = address(sentinel);

    assembly {
      let freeMemoryPointer := mload(0x40)
      mstore(0, 0xa1054f6b)
      mstore(0x20, borrowerAddress)
      mstore(0x40, accountAddress)
      mstore(0x60, tokenAddress)
      if iszero(
        and(eq(returndatasize(), 0x20), call(gas(), sentinelAddress, 0, 0x1c, 0x64, 0, 0x20))
      ) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
      escrow := mload(0)
      mstore(0x40, freeMemoryPointer)
      mstore(0x60, 0)
    }
  }
}
