// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { IChainalysisSanctionsList } from './interfaces/IChainalysisSanctionsList.sol';
import { IWildcatSanctionsSentinel } from './interfaces/IWildcatSanctionsSentinel.sol';
import { WildcatSanctionsEscrow } from './WildcatSanctionsEscrow.sol';

contract WildcatSanctionsSentinel is IWildcatSanctionsSentinel {
  // ========================================================================== //
  //                                  Constants                                 //
  // ========================================================================== //

  bytes32 public constant override WildcatSanctionsEscrowInitcodeHash =
    keccak256(type(WildcatSanctionsEscrow).creationCode);

  address public immutable override chainalysisSanctionsList;

  address public immutable override archController;

  // ========================================================================== //
  //                                   Storage                                  //
  // ========================================================================== //

  TmpEscrowParams public override tmpEscrowParams;

  mapping(address borrower => mapping(address account => bool sanctionOverride))
    public
    override sanctionOverrides;

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor(address _archController, address _chainalysisSanctionsList) {
    // 1. 设置 archController
    archController = _archController;
    // 2. 设置 chainalysisSanctionsList
    chainalysisSanctionsList = _chainalysisSanctionsList;
    // 3. 重置 tmpEscrowParams
    _resetTmpEscrowParams();
  }

  // ========================================================================== //
  //                              Internal Helpers                              //
  // ========================================================================== //

  function _resetTmpEscrowParams() internal {
    // 设置 tmpEscrowParams 为默认值
    tmpEscrowParams = TmpEscrowParams(address(1), address(1), address(1));
  }

  /**
   * @dev Derive create2 salt for an escrow given the borrower, account and asset.
   *      name prefix and symbol prefix.
   */
    /**
   * @dev 根据借款人、账户和资产派生出托管合约的 create2 盐值。
   *      名称前缀和符号前缀。
   */
  function _deriveSalt(
    address borrower,
    address account,
    address asset
  ) internal pure returns (bytes32 salt) {
    assembly {
      // 缓存自由内存指针
      // Cache free memory pointer
      let freeMemoryPointer := mload(0x40)
      // `keccak256(abi.encode(borrower, account, asset))`
      mstore(0x00, borrower) // 存储 borrower
      mstore(0x20, account) // 存储 account
      mstore(0x40, asset) // 存储 asset
      salt := keccak256(0, 0x60) // 计算盐值
      // Restore free memory pointer
      mstore(0x40, freeMemoryPointer)
    }
  }

  // ========================================================================== //
  //                              Sanction Queries                              //
  // ========================================================================== //

  /**
   * //返回 boolean 值，指示 `account` 是否在 Chainalysis 的制裁名单上。
   * @dev Returns boolean indicating whether `account` is sanctioned on Chainalysis.
   */
  function isFlaggedByChainalysis(address account) public view override returns (bool) {
    return IChainalysisSanctionsList(chainalysisSanctionsList).isSanctioned(account);
  }

  /**
   * 1.指定的 account 是否在 Chainalysis 的制裁名单上。
   * 2. 这个制裁状态是否没有被 borrower 覆盖或取消。
   * @dev Returns boolean indicating whether `account` is sanctioned on Chainalysis
   *      and that status has not been overridden by `borrower`.
   */
  function isSanctioned(address borrower, address account) public view override returns (bool) {
    // 1. 检查 account 是否在 Chainalysis 的制裁名单上
    // 2. 检查这个制裁状态是否没有被 borrower 覆盖或取消
    return !sanctionOverrides[borrower][account] && isFlaggedByChainalysis(account);
  }

  // ========================================================================== //
  //                             Sanction Overrides                             //
  // ========================================================================== //

  /** 
   * @dev Overrides the sanction status of `account` for `borrower`.
   */
  function overrideSanction(address account) public override {
    // 1. 设置 sanctionOverrides 为 true
    sanctionOverrides[msg.sender][account] = true;
    // 2. 触发 SanctionOverride 事件
    emit SanctionOverride(msg.sender, account);
  }

  /**移除制裁覆盖
   * @dev Removes the sanction override of `account` for `borrower`.
   */
  function removeSanctionOverride(address account) public override {
    sanctionOverrides[msg.sender][account] = false;
    emit SanctionOverrideRemoved(msg.sender, account);
  }

  // ========================================================================== //
  //                              Escrow Deployment                             //
  // ========================================================================== //

  /**
   * @dev Creates a new WildcatSanctionsEscrow contract for `borrower`,
   *      `account`, and `asset` or returns the existing escrow contract
   *      if one already exists.
   *
   *      The escrow contract is added to the set of sanction override
   *      addresses for `borrower` so that it can not be blocked.
   */
/**
   * @dev 为 `borrower`、`account` 和 `asset` 创建一个新的 WildcatSanctionsEscrow 合约，
   *      如果已经存在，则返回现有的托管合约。
   *
   *      该托管合约会被添加到 `borrower` 的制裁覆盖地址集合中，
   *      以确保它不会被阻止。
   * */
   //@audit 没有校验borrower、account和asset是否为0地址
  function createEscrow(
    address borrower,
    address account,
    address asset
  ) public override returns (address escrowContract) {
    // 获取 escrowContract 地址
    escrowContract = getEscrowAddress(borrower, account, asset);

    // Skip creation if the address code size is non-zero
    // 如果 escrowContract 的代码长度不为零，则直接返回escrowContract地址
    if (escrowContract.code.length != 0) return escrowContract;
    // 设置 tmpEscrowParams
    tmpEscrowParams = TmpEscrowParams(borrower, account, asset);
    // 创建新的 WildcatSanctionsEscrow 合约
    // { salt: ... } 语法是 Solidity 提供的语法糖，
    // 用于指定使用 CREATE2 进行部署，并提供 salt 值。
    new WildcatSanctionsEscrow{ salt: _deriveSalt(borrower, account, asset) }();
    // 触发 NewSanctionsEscrow 事件
    emit NewSanctionsEscrow(borrower, account, asset);
    // 设置制裁覆盖
    sanctionOverrides[borrower][escrowContract] = true;
    // 触发 SanctionOverride 事件

    emit SanctionOverride(borrower, escrowContract);
    // 重置 tmpEscrowParams
    _resetTmpEscrowParams();
  }

  /**
   * @dev Calculate the create2 escrow address for the combination
   *      of `borrower`, `account`, and `asset`.
   */
    /**
   * @dev 计算 `borrower`、`account` 和 `asset` 组合的 create2 托管地址。
   */
  function getEscrowAddress(
    address borrower,
    address account,
    address asset
  ) public view override returns (address escrowAddress) {
    // 1. 获取盐值
    bytes32 salt = _deriveSalt(borrower, account, asset);
    // 2. 获取 initCodeHash
    bytes32 initCodeHash = WildcatSanctionsEscrowInitcodeHash;
    assembly {
      // 缓存自由内存指针
      // Cache the free memory pointer so it can be restored at the end
      let freeMemoryPointer := mload(0x40)
      // 将 0xff + address(this) 写入 bytes 11:32
      // Write 0xff + address(this) to bytes 11:32
      // 这个操作的目的是创建一个 32 字节的值，其中：
      // 第一个字节是 0xff
      // 接下来 11 个字节是 0
      // 最后 20 个字节是当前合约的地址
      mstore(0x00, or(0xff0000000000000000000000000000000000000000, address()))

      // Write salt to bytes 32:64
      // 将盐值写入 bytes 32:64
      mstore(0x20, salt)

      // Write initcode hash to bytes 64:96
      // 将 initCodeHash 写入 bytes 64:96
      mstore(0x40, initCodeHash)

      // Calculate create2 hash
      // 计算 create2 哈希
      //@audit 0x 16进制
      
      // 0x0b 在十进制中是 11
      // 这正好跳过了前面的 0xff 和 11 个零字节
      // 为什么跳过：
      // CREATE2 地址计算不需要包含 0xff 前缀
      // 跳过这 11 个字节后，正好从合约地址开始读取
      // and(..., 0xffffffffffffffffffffffffffffffffffffffff):
      // 这是一个位与操作，用于将计算得到的哈希值截断为 20 字节（160 位）。
      escrowAddress := and(keccak256(0x0b, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)

      // Restore the free memory pointer
      mstore(0x40, freeMemoryPointer)
    }
  }
}
