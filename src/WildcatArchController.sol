// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import { EnumerableSet } from 'openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import 'solady/auth/Ownable.sol';
import './spherex/SphereXConfig.sol';
import './libraries/MathUtils.sol';
import './interfaces/ISphereXProtectedRegisteredBase.sol';

contract WildcatArchController is SphereXConfig, Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  // ========================================================================== //
  //                                   Storage                                  //
  // ========================================================================== //

  EnumerableSet.AddressSet internal _markets;
  EnumerableSet.AddressSet internal _controllerFactories;
  EnumerableSet.AddressSet internal _borrowers;
  EnumerableSet.AddressSet internal _controllers;
  EnumerableSet.AddressSet internal _assetBlacklist;

  // ========================================================================== //
  //                              Events and Errors                             //
  // ========================================================================== //

  error NotControllerFactory();
  error NotController();

  error BorrowerAlreadyExists();
  error ControllerFactoryAlreadyExists();
  error ControllerAlreadyExists();
  error MarketAlreadyExists();

  error BorrowerDoesNotExist();
  error AssetAlreadyBlacklisted();
  error ControllerFactoryDoesNotExist();
  error ControllerDoesNotExist();
  error AssetNotBlacklisted();
  error MarketDoesNotExist();

  event MarketAdded(address indexed controller, address market);
  event MarketRemoved(address market);

  event ControllerFactoryAdded(address controllerFactory);
  event ControllerFactoryRemoved(address controllerFactory);

  event BorrowerAdded(address borrower);
  event BorrowerRemoved(address borrower);

  event AssetBlacklisted(address asset);
  event AssetPermitted(address asset);

  event ControllerAdded(address indexed controllerFactory, address controller);
  event ControllerRemoved(address controller);

  // ========================================================================== //
  //                                 Constructor                                //
  // ========================================================================== //

  constructor() SphereXConfig(msg.sender, address(0), address(0)) {
    _initializeOwner(msg.sender);
  }

  // ========================================================================== //
  //                            SphereX Engine Update                           //
  // ========================================================================== //

  /**
   * @dev Update SphereX engine on registered contracts and add them as
   *      allowed senders on the engine contract.
   *   * @dev 更新已注册合约上的 SphereX 引擎，并将它们添加为
   *      引擎合约上的允许发送者。 
   */
  
  function updateSphereXEngineOnRegisteredContracts(
    address[] calldata controllerFactories,
    address[] calldata controllers,
    address[] calldata markets
  ) external spherexOnlyOperatorOrAdmin {
    address engineAddress = sphereXEngine();// 获取当前引擎地址
    //abi.encodeWithSelector(...):
    //这是一个 Solidity 内置函数，用于编码函数调用。
    //它将函数选择器和参数打包成可以直接用于低级调用的格式。
    //.selector 语法：
    // 当应用于一个函数时，.selector 返回该函数的选择器。
    // 这是一种简便的方法来获取函数的选择器，而不需要手动计算哈希。
    bytes memory changeSphereXEngineCalldata = abi.encodeWithSelector(
      ISphereXProtectedRegisteredBase.changeSphereXEngine.selector,
      engineAddress
    );
    bytes memory addAllowedSenderOnChainCalldata;
    // 如果引擎地址不为零，则添加允许发送者到链上
    //这段代码是在准备一个函数调用，以便稍后可以动态
    //地将不同的地址添加为 SphereX 引擎上的允许发送者。
    //这种方法允许灵活地管理多个合约的权限
    if (engineAddress != address(0)) {
      addAllowedSenderOnChainCalldata = abi.encodeWithSelector(
        ISphereXEngine.addAllowedSenderOnChain.selector,
        address(0)
      );
    }
    _updateSphereXEngineOnRegisteredContractsInSet(
      _controllerFactories,
      engineAddress,
      controllerFactories,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      ControllerFactoryDoesNotExist.selector
    );
    _updateSphereXEngineOnRegisteredContractsInSet(
      _controllers,
      engineAddress,
      controllers,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      ControllerDoesNotExist.selector
    );
    _updateSphereXEngineOnRegisteredContractsInSet(
      _markets,
      engineAddress,
      markets,
      changeSphereXEngineCalldata,
      addAllowedSenderOnChainCalldata,
      MarketDoesNotExist.selector
    );
  }
  // 更新 SphereX 引擎在注册合约中的地址
  function _updateSphereXEngineOnRegisteredContractsInSet(
    EnumerableSet.AddressSet storage set,// 存储合约地址的集合
    address engineAddress,// 引擎地址
    address[] memory contracts,// 合约地址数组
    bytes memory changeSphereXEngineCalldata,// 更改引擎地址的函数调用数据
    bytes memory addAllowedSenderOnChainCalldata,// 添加允许发送者到链上的函数调用数据
    bytes4 notInSetErrorSelectorBytes// 错误选择器
  ) internal {
    for (uint256 i = 0; i < contracts.length; i++) {
      address account = contracts[i];// 合约地址
      if (!set.contains(account)) {// 如果集合中不包含该地址
        // 将错误选择器转换为 uint32
        uint32 notInSetErrorSelector = uint32(notInSetErrorSelectorBytes);
        // 使用 assembly 块来执行低级操作，如存储数据和抛出错误
        assembly {
          // 将错误选择器存储在内存的 0 位置
          mstore(0, notInSetErrorSelector)
          // 从内存的 0x1c 位置开始，长度为 4 字节的数据
          revert(0x1c, 0x04)
        }
      }
      // 调用合约的 changeSphereXEngine 函数，传递引擎地址作为参数
      _callWith(account, changeSphereXEngineCalldata);
      // 如果引擎地址不为零，则将该合约地址添加为允许的发送者
      if (engineAddress != address(0)) {
        assembly {
          //这是之前在代码中准备的函数调用数据。它可能看起来像这样：
        //          addAllowedSenderOnChainCalldata = abi.encodeWithSelector(
        //    ISphereXEngine.addAllowedSenderOnChain.selector,
        //    address(0)
        //  );
          // 这个数据的结构如下：
          // 前 4 字节：函数选择器
          // 接下来的 32 字节：一个地址参数（初始设置为 address(0)）
          // 2. 0x24:
          // 这个值代表 36 字节的偏移量。为什么是 36 字节？让我们分解一下：
          // 0x00 - 0x03 (4 字节)：函数选择器
          // 0x04 - 0x23 (32 字节)：第一个参数（地址）
          // 0x24：这就是我们要修改的地址参数的起始位置
          mstore(add(addAllowedSenderOnChainCalldata, 0x24), account)
        }
        // 调用引擎合约的 addAllowedSenderOnChain 函数，传递合约地址作为参数
        _callWith(engineAddress, addAllowedSenderOnChainCalldata);
        // 触发 NewAllowedSenderOnchain 事件，传递合约地址作为参数
        emit_NewAllowedSenderOnchain(account);
      }
    }
  }

  function _callWith(address target, bytes memory data) internal {
    assembly {
      //call 函数执行外部调用，参数如下：
      //gas(): 剩余的 gas
      //target: 目标合约地址
      //0: 发送的 ETH 数量（这里是 0）
      //add(data, 0x20): 输入数据的内存位置（跳过长度前缀）
      //mload(data): 输入数据的长度
      //0, 0: 输出数据的内存位置和长度（这里不使用）
      //iszero 检查调用是否失败（返回 0）
      //call 函数在成功时返回 1，失败时返回 0。
      // iszero(call(...)) 的结果：
      // 如果调用成功（返回 1），iszero 会返回 0（false）
      // 如果调用失败（返回 0），iszero 会返回 1（true）
      // 因此，if 语句内的代码块只有在调用失败时才会执行。
      if iszero(call(gas(), target, 0, add(data, 0x20), mload(data), 0, 0)) {
        //如果调用失败，这行将返回的数据复制到内存中：
        // 0: 目标内存位置
        // 0: 返回数据的起始位置
        // returndatasize(): 返回数据的长度
        //从内存的0位置开始，复制returndatasize()长度的数据到内存的0位置
        //返回数据缓冲区：这是一个特殊的内存区域，用于存储外部调用的返回数据。它不是常规的 Solidity 内存空间。
        // Solidity 的内存空间：这是合约可以直接读写的内存区域。
        // returndatacopy 函数的作用是将数据从返回数据缓冲区复制到 Solidity 的内存空间。它的参数含义如下：
        //第一个 0：目标位置（在 Solidity 内存中）
        //第二个 0：源位置（在返回数据缓冲区中）
        //returndatasize()：要复制的字节数
        returndatacopy(0, 0, returndatasize())
        //这行触发了一个 revert 操作。
        // 0 是内存中返回数据的起始位置。
        // returndatasize() 是返回数据的长度。
        //返回起始位置为0，长度为returndatasize()的内存数据
        revert(0, returndatasize())
      }
    }
  }

  /* ========================================================================== */
  /*                                  Borrowers                                 */
  /* ========================================================================== */
  // 注册借款人 //@audit 无限添加borrower
  function registerBorrower(address borrower) external onlyOwner {
    // 将借款人地址添加到 _borrowers 集合中
    if (!_borrowers.add(borrower)) {
      revert BorrowerAlreadyExists();
    }
    emit BorrowerAdded(borrower);
  }
  // 删除借款人
  function removeBorrower(address borrower) external onlyOwner {
    if (!_borrowers.remove(borrower)) {
      revert BorrowerDoesNotExist();
    }
    emit BorrowerRemoved(borrower);
  }
  // 判断是否注册借款人
  function isRegisteredBorrower(address borrower) external view returns (bool) {
    return _borrowers.contains(borrower);
  }
  // 获取注册借款人
  function getRegisteredBorrowers() external view returns (address[] memory) {
    return _borrowers.values();
  }
  // 获取注册借款人
  function getRegisteredBorrowers(
    uint256 start,// 开始索引 
    uint256 end// 结束索引
  ) external view returns (address[] memory arr) {
    uint256 len = _borrowers.length();// 获取注册借款人数量
    end = MathUtils.min(end, len);// 结束索引
    uint256 count = end - start;
    arr = new address[](count); // 创建数组
    //@audit dos漏洞
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _borrowers.at(start + i); // 获取注册借款人
    }
  }

  function getRegisteredBorrowersCount() external view returns (uint256) {
    return _borrowers.length();
  }

  // ========================================================================== //
  //                          Asset Blacklist Registry                          //
  // ========================================================================== //

  function addBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.add(asset)) {
      revert AssetAlreadyBlacklisted();
    }
    emit AssetBlacklisted(asset);
  }

  function removeBlacklist(address asset) external onlyOwner {
    if (!_assetBlacklist.remove(asset)) {
      revert AssetNotBlacklisted();
    }
    emit AssetPermitted(asset);
  }

  function isBlacklistedAsset(address asset) external view returns (bool) {
    return _assetBlacklist.contains(asset);
  }

  function getBlacklistedAssets() external view returns (address[] memory) {
    return _assetBlacklist.values();
  }

  function getBlacklistedAssets(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    uint256 len = _assetBlacklist.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _assetBlacklist.at(start + i);
    }
  }

  function getBlacklistedAssetsCount() external view returns (uint256) {
    return _assetBlacklist.length();
  }



  /* ========================================================================== */
  /*                            Controller Factories                            */
  /* ========================================================================== */

  function registerControllerFactory(address factory) external onlyOwner {
    if (!_controllerFactories.add(factory)) {
      revert ControllerFactoryAlreadyExists();
    }
    _addAllowedSenderOnChain(factory);
    emit ControllerFactoryAdded(factory);
  }

  function removeControllerFactory(address factory) external onlyOwner {
    if (!_controllerFactories.remove(factory)) {
      revert ControllerFactoryDoesNotExist();
    }
    emit ControllerFactoryRemoved(factory);
  }

  function isRegisteredControllerFactory(address factory) external view returns (bool) {
    return _controllerFactories.contains(factory);
  }

  function getRegisteredControllerFactories() external view returns (address[] memory) {
    return _controllerFactories.values();
  }

  function getRegisteredControllerFactories(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    uint256 len = _controllerFactories.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllerFactories.at(start + i);
    }
  }

  function getRegisteredControllerFactoriesCount() external view returns (uint256) {
    return _controllerFactories.length();
  }

  /* ========================================================================== */
  /*                                 Controllers                                */
  /* ========================================================================== */

  modifier onlyControllerFactory() {
    if (!_controllerFactories.contains(msg.sender)) {
      revert NotControllerFactory();
    }
    _;
  }

  function registerController(address controller) external onlyControllerFactory {
    if (!_controllers.add(controller)) {
      revert ControllerAlreadyExists();
    }
    _addAllowedSenderOnChain(controller);
    emit ControllerAdded(msg.sender, controller);
  }

  function removeController(address controller) external onlyOwner {
    if (!_controllers.remove(controller)) {
      revert ControllerDoesNotExist();
    }
    emit ControllerRemoved(controller);
  }

  function isRegisteredController(address controller) external view returns (bool) {
    return _controllers.contains(controller);
  }

  function getRegisteredControllers() external view returns (address[] memory) {
    return _controllers.values();
  }

  function getRegisteredControllers(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    uint256 len = _controllers.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _controllers.at(start + i);
    }
  }

  function getRegisteredControllersCount() external view returns (uint256) {
    return _controllers.length();
  }

  /* ========================================================================== */
  /*                                   Markets                                   */
  /* ========================================================================== */

  modifier onlyController() {
    if (!_controllers.contains(msg.sender)) {
      revert NotController();
    }
    _;
  }

  function registerMarket(address market) external onlyController {
    if (!_markets.add(market)) {
      revert MarketAlreadyExists();
    }
    _addAllowedSenderOnChain(market);
    emit MarketAdded(msg.sender, market);
  }

  function removeMarket(address market) external onlyOwner {
    if (!_markets.remove(market)) {
      revert MarketDoesNotExist();
    }
    emit MarketRemoved(market);
  }

  function isRegisteredMarket(address market) external view returns (bool) {
    return _markets.contains(market);
  }

  function getRegisteredMarkets() external view returns (address[] memory) {
    return _markets.values();
  }

  function getRegisteredMarkets(
    uint256 start,
    uint256 end
  ) external view returns (address[] memory arr) {
    uint256 len = _markets.length();
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _markets.at(start + i);
    }
  }

  function getRegisteredMarketsCount() external view returns (uint256) {
    return _markets.length();
  }
}
