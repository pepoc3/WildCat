// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import './libraries/LibERC20.sol';
import './interfaces/IWildcatArchController.sol';
import './libraries/LibStoredInitCode.sol';
import './libraries/MathUtils.sol';
import './ReentrancyGuard.sol';
import './interfaces/WildcatStructsAndEnums.sol';
import './access/IHooks.sol';
import './IHooksFactory.sol';
import './types/TransientBytesArray.sol';
import './spherex/SphereXProtectedRegisteredBase.sol';

struct TmpMarketParameterStorage {
  address borrower;
  address asset;
  address feeRecipient;
  uint16 protocolFeeBips;
  uint128 maxTotalSupply;
  uint16 annualInterestBips;
  uint16 delinquencyFeeBips;
  uint32 withdrawalBatchDuration;
  uint16 reserveRatioBips;
  uint32 delinquencyGracePeriod;
  bytes32 packedNameWord0;
  bytes32 packedNameWord1;
  bytes32 packedSymbolWord0;
  bytes32 packedSymbolWord1;
  uint8 decimals;
  HooksConfig hooks;
}

contract HooksFactory is SphereXProtectedRegisteredBase, ReentrancyGuard, IHooksFactory {
  using LibERC20 for address;

  TransientBytesArray internal constant _tmpMarketParameters =
    TransientBytesArray.wrap(uint256(keccak256('Transient:TmpMarketParametersStorage')) - 1);

  uint256 internal immutable ownCreate2Prefix = LibStoredInitCode.getCreate2Prefix(address(this));

  address public immutable override marketInitCodeStorage;

  uint256 public immutable override marketInitCodeHash;

  address public immutable override sanctionsSentinel;

  address[] internal _hooksTemplates;
  mapping(address hooksTemplate => address[] markets) internal _marketsByHooksTemplate;
  mapping(address hooksTemplate => HooksTemplate details) internal _templateDetails;
  mapping(address hooksInstance => address hooksTemplate)
    public
    override getHooksTemplateForInstance;

  constructor(
    address archController_,
    address _sanctionsSentinel,
    address _marketInitCodeStorage,
    uint256 _marketInitCodeHash
  ) {
    marketInitCodeStorage = _marketInitCodeStorage;
    marketInitCodeHash = _marketInitCodeHash;
    _archController = archController_;
    sanctionsSentinel = _sanctionsSentinel;
    __SphereXProtectedRegisteredBase_init(IWildcatArchController(archController_).sphereXEngine());
  }

  /**
   * @dev Registers the factory as a controller with the arch-controller, allowing
   *      it to register new markets.
   *      Needs to be executed once at deployment.
   *      Does not need checks for whether it has already been registered as the
   *      arch-controller will revert if it is already registered.
   */
  /**
 * @dev 将工厂注册为 arch-controller 的控制器，允许它注册新的市场。
 *      需要在部署时执行一次。
 *      不需要检查是否已经注册，因为如果已经注册，arch-controller 会自动回滚。
 */
  function registerWithArchController() external override {
    IWildcatArchController(_archController).registerController(address(this));
  }
  //返回arch-controller地址
  function archController() external view override returns (address) {
    return _archController;
  }

  // ========================================================================== //
  //                          Internal Storage Helpers                          //
  // ========================================================================== //

  /**
   * @dev 从临时存储中获取市场参数。
   * @dev Get the temporary market parameters from transient storage.
   */
  function _getTmpMarketParameters()
    internal
    view
    returns (TmpMarketParameterStorage memory parameters)
  {
    //_tmpMarketParameters 确实是一个常量，但它只是一个标识符或"指针"，指向瞬态存储中的特定位置。
    // 这个常量值本身并不存储实际数据，而是用来确定在瞬态存储中读写数据的位置。
    //解码的必要性：
    // 当我们向这个位置写入数据时，通常会使用 abi.encode 将结构化数据编码为字节数组。
    // 因此，当读取数据时，需要使用 abi.decode 来将字节数组转换回结构化数据。
    return abi.decode(_tmpMarketParameters.read(), (TmpMarketParameterStorage));
  }

  /**
   * @dev Set the temporary market parameters in transient storage.
   */
  function _setTmpMarketParameters(TmpMarketParameterStorage memory parameters) internal {
    _tmpMarketParameters.write(abi.encode(parameters));
  }

  // ========================================================================== //
  //                                  Modifiers                                 //
  // ========================================================================== //

  modifier onlyArchControllerOwner() {
    if (msg.sender != IWildcatArchController(_archController).owner()) {
      revert CallerNotArchControllerOwner();
    }
    _;
  }

  // ========================================================================== //
  //                               Hooks Templates                              //
  // ========================================================================== //

  function addHooksTemplate(
    address hooksTemplate,// hooks 模板。 
    string calldata name,// 模板的名称。
    address feeRecipient,//收取费用的接收方。
    address originationFeeAsset,//收取费用的资产。  
    uint80 originationFeeAmount,//收取费用的金额。
    uint16 protocolFeeBips//协议费用的百分比。
  ) external override onlyArchControllerOwner {
    //@audit 没有检查exists
    if (_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateAlreadyExists();
    }
    _validateFees(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
    _templateDetails[hooksTemplate] = HooksTemplate({
      exists: true,
      name: name,
      feeRecipient: feeRecipient,
      originationFeeAsset: originationFeeAsset,
      originationFeeAmount: originationFeeAmount,
      protocolFeeBips: protocolFeeBips,
      enabled: true,
      index: uint24(_hooksTemplates.length)
    });
    _hooksTemplates.push(hooksTemplate);
    emit HooksTemplateAdded(
      hooksTemplate,
      name,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function _validateFees(
    address feeRecipient,//收取费用的接收方。 
    address originationFeeAsset,//收取费用的资产。
    //这是一次性收取的费用，通常在创建新市场或执行特定操作时收取。
    // 是一个固定金额，而不是百分比。
    //只在特定事件（如市场创建）时收取一次。
    //可能用于补偿初始设置成本或作为进入门槛。
    uint80 originationFeeAmount,
    //protocolFeeBips 用于定义协议从每笔交易或操作中收取的费用比例。
    //"bips" 是 "basis points" 的缩写，1 bip = 0.01%。
    uint16 protocolFeeBips
  ) internal pure {
    //如果 originationFeeAmount 大于 0，则 hasOriginationFee 为 true，表示需要收取发起费用。
    bool hasOriginationFee = originationFeeAmount > 0;
    //如果 feeRecipient 是零地址（0x0），则 nullFeeRecipient 为 true。
    bool nullFeeRecipient = feeRecipient == address(0);
    //如果 originationFeeAsset 是零地址，则 nullOriginationFeeAsset 为 true。
    bool nullOriginationFeeAsset = originationFeeAsset == address(0);
    //@audit 可能遗漏的边界情况：
    // 1. protocolFeeBips 为零但 feeRecipient 不为零的情况。
    // 这可能是允许的，但值得考虑是否需要检查。
    // 2. originationFeeAmount 为零但 originationFeeAsset 不为零的情况。
    // 这种情况下，可能应该要求 originationFeeAsset 也为零。
    // 3. originationFeeAmount 的上限检查。虽然 uint80 提供了一个隐含的上限，
    // 但可能需要一个更合理的业务逻辑上限。
    // 4. 没有检查 feeRecipient 和 originationFeeAsset 是否为有效的地址
    // （例如，是否为合约地址）。
    if (
      //检查：如果设置了协议费用比例，但没有指定费用接收方（接收方地址为0）。
      (protocolFeeBips > 0 && nullFeeRecipient) ||
      // 检查：如果有发起费用，但没有指定费用接收方。
      (hasOriginationFee && nullFeeRecipient) ||
      //检查：如果有发起费用，但没有指定费用资产（资产地址为0）。
      (hasOriginationFee && nullOriginationFeeAsset) ||
      //检查：协议费用百分比不超过 10%。
      protocolFeeBips > 1_000
    ) {
      revert InvalidFeeConfiguration();
    }
  }

  /// @dev Update the fees for a hooks template
  /// Note: The new fee structure will apply to all NEW markets created with existing
  ///       or future instances of the hooks template, and the protocol fee can be pushed
  ///       to existing markets using `pushProtocolFeeBipsUpdates`.
  /// @dev 更新钩子模板的费用
  /// 注意：新的费用结构将应用于使用现有或未来钩子模板实例创建的所有新市场，
  ///       并且可以使用 `pushProtocolFeeBipsUpdates` 函数将协议费用推送到现有市场。
  function updateHooksTemplateFees(
    address hooksTemplate,
    address feeRecipient,
    address originationFeeAsset,
    uint80 originationFeeAmount,
    uint16 protocolFeeBips
  ) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    _validateFees(feeRecipient, originationFeeAsset, originationFeeAmount, protocolFeeBips);
    //从 _templateDetails 映射中获取与 hooksTemplate 地址对应的 HooksTemplate 结构体
    HooksTemplate storage template = _templateDetails[hooksTemplate];
    template.feeRecipient = feeRecipient;
    template.originationFeeAsset = originationFeeAsset;
    template.originationFeeAmount = originationFeeAmount;
    template.protocolFeeBips = protocolFeeBips;
    emit HooksTemplateFeesUpdated(
      hooksTemplate,
      feeRecipient,
      originationFeeAsset,
      originationFeeAmount,
      protocolFeeBips
    );
  }

  function disableHooksTemplate(address hooksTemplate) external override onlyArchControllerOwner {
    if (!_templateDetails[hooksTemplate].exists) {
      revert HooksTemplateNotFound();
    }
    _templateDetails[hooksTemplate].enabled = false;
    // Emit an event to indicate that the template has been removed
    emit HooksTemplateDisabled(hooksTemplate);
  }

  function getHooksTemplateDetails(
    address hooksTemplate
  ) external view override returns (HooksTemplate memory) {
    return _templateDetails[hooksTemplate];
  }

  function isHooksTemplate(address hooksTemplate) external view override returns (bool) {
    return _templateDetails[hooksTemplate].exists;
  }

  function getHooksTemplates() external view override returns (address[] memory) {
    return _hooksTemplates;
  }

  function getHooksTemplates(
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    uint256 len = _hooksTemplates.length;
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = _hooksTemplates[start + i];
    }
  }

  function getHooksTemplatesCount() external view override returns (uint256) {
    return _hooksTemplates.length;
  }

  function getMarketsForHooksTemplate(
    address hooksTemplate
  ) external view override returns (address[] memory) {
    return _marketsByHooksTemplate[hooksTemplate];
  }

  function getMarketsForHooksTemplate(
    address hooksTemplate,
    uint256 start,
    uint256 end
  ) external view override returns (address[] memory arr) {
    address[] storage markets = _marketsByHooksTemplate[hooksTemplate];
    uint256 len = markets.length;
    end = MathUtils.min(end, len);
    uint256 count = end - start;
    arr = new address[](count);
    for (uint256 i = 0; i < count; i++) {
      arr[i] = markets[start + i];
    }
  }

  function getMarketsForHooksTemplateCount(
    address hooksTemplate
  ) external view override returns (uint256) {
    return _marketsByHooksTemplate[hooksTemplate].length;
  }

  // ========================================================================== //
  //                               Hooks Instances                              //
  // ========================================================================== //

  /// @dev Deploy a hooks instance for an approved template with constructor args.
  ///      Callable by approved borrowers on the arch-controller.
  ///      May require payment of origination fees.
  /// @dev 为已批准的模板部署一个带有构造函数参数的钩子实例。
  ///      可由 arch-controller 上的已批准借款人调用。
  ///      可能需要支付发起费用。
  function deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) external override nonReentrant returns (address hooksInstance) {
    //这段代码的作用是确保只有在 ArchController 
    // 中注册为借款人的地址才能执行后续操作
    if (!IWildcatArchController(_archController).isRegisteredBorrower(msg.sender)) {
      revert NotApprovedBorrower();
    }
    hooksInstance = _deployHooksInstance(hooksTemplate, constructorArgs);
  }

  function isHooksInstance(address hooksInstance) external view override returns (bool) {
    return getHooksTemplateForInstance[hooksInstance] != address(0);
  }

  function _deployHooksInstance(
    address hooksTemplate,
    bytes calldata constructorArgs
  ) internal returns (address hooksInstance) {
    // 获取 hooksTemplate 的 HooksTemplate 结构体
    HooksTemplate storage template = _templateDetails[hooksTemplate];
    // 检查模板是否存在
    if (!template.exists) {
      revert HooksTemplateNotFound();
    }
    // 检查模板是否启用
    if (!template.enabled) {
      revert HooksTemplateNotAvailable();
    }

    assembly {
      // 获取初始化代码的指针
      let initCodePointer := mload(0x40)
      // 获取初始化代码的大小
      // 1. extcodesize(hooksTemplate) 返回 hooksTemplate 地址处合约的字节码大小。
      // 2. 通常，Solidity 编译器会在合约字节码的末尾添加一个 STOP 操作码（0x00），以确保执行到达代码末尾时停止。
      // 3. 通过减去1，我们排除了这个 STOP 操作码，只获取实际的合约逻辑代码。
      // 4. 这样做的原因可能是为了准确复制合约的初始化代码，而不包括自动添加的 STOP 操作码。
      // 5. 在后续的代码中，这个 initCodeSize 被用于从 hooksTemplate 复制代码到内存中，以便部署新的合约实例。
      let initCodeSize := sub(extcodesize(hooksTemplate), 1)
      // Copy code from target address to memory starting at byte 1
      // 1. hooksTemplate: 源地址，即要复制代码的合约地址。
      // 2. initCodePointer: 目标地址，即内存中开始存储复制代码的位置。
      // 3. 1: 源偏移量，表示从合约代码的第二个字节开始复制。
      //    这里使用 1 而不是 0 是为了跳过合约代码开头的长度前缀。
      // 4. initCodeSize: 要复制的字节数。
      // 这行代码的目的是将 hooksTemplate 合约的初始化代码
      // （不包括开头的长度前缀）复制到内存中，以便后续用于部署新的合约实例。
      extcodecopy(hooksTemplate, initCodePointer, 1, initCodeSize)
      // 将 initCodePointer 和 initCodeSize 相加，得到新的指针
      let endInitCodePointer := add(initCodePointer, initCodeSize)
      // Write the address of the caller as the first parameter
      // 1. endInitCodePointer 是一个内存指针，指向初始化代码结束后的位置。
      // 2. caller() 是一个 Solidity 内置函数，返回当前函数调用的发起者地址。
      // 3. mstore(a, v) 是一个汇编指令，用于将 32 字节的值 v 存储到内存地址 a 处。
      // 所以，这行代码的具体作用是：
      // 将当前函数调用者的地址（20 字节）存储到 endInitCodePointer 指向的内存位置。
      // 这个地址会被作为新部署的合约的构造函数的第一个参数。
      mstore(endInitCodePointer, caller())
      // Write the offset to the encoded constructor args
      //       内存布局:

      // 地址            内容
      // +------------+--------------------------------+
      // | 0x00       | 初始化代码                      |
      // | ...        | ...                            |
      // +------------+--------------------------------+
      // | endInitCodePointer    | 调用者地址 (32 字节)  |
      // +------------+--------------------------------+
      // | endInitCodePointer    | 0x40 (32 字节)       |
      // | + 0x20     |                                |
      // +------------+--------------------------------+
      // | endInitCodePointer    | 构造函数参数长度      |
      // | + 0x40     |                                |
      // +------------+--------------------------------+
      // | endInitCodePointer    | 实际构造函数参数      |
      // | + 0x60     |                                |
      // +------------+--------------------------------+
      mstore(add(endInitCodePointer, 0x20), 0x40)
      // Write the length of the encoded constructor args
      let constructorArgsSize := constructorArgs.length
      mstore(add(endInitCodePointer, 0x40), constructorArgsSize)
      // Copy constructor args to initcode after the bytes length
      // 1.calldatacopy(destOffset, offset, length) 是一个 EVM 操作码，用于将调用数据复制到内存中。
      // destOffset: 目标内存位置
      // offset: 调用数据中的起始偏移量
      // length: 要复制的字节数
      // 2.add(endInitCodePointer, 0x60):
      // 计算目标内存位置，即初始化代码结束后的 96 字节（0x60 十六进制）处。
      // 这个位置正好在之前存储的调用者地址、偏移量和参数长度之后。
      // 3.constructorArgs.offset:
      // 表示构造函数参数在调用数据中的起始位置。
      // 4.constructorArgsSize:
      // 表示构造函数参数的总字节长度。
      // 这行代码的作用是：
      // 将调用数据中的构造函数参数复制到内存中，紧接在之前准备的数据之后。
      calldatacopy(add(endInitCodePointer, 0x60), constructorArgs.offset, constructorArgsSize)
      // Get the full size of the initcode with the constructor args
      // add(add(initCodeSize, 0x60), constructorArgsSize) 的计算过程是：
      // 1. 首先将 initCodeSize 和 0x60 相加，得到包含初始化代码和额外数据的大小。
      // 2. 然后再加上 constructorArgsSize，得到完整的初始化代码大小，包括所有必要的数据。
      // 3. 这个计算结果 initCodeSizeWithArgs 将在后续的 create 操作中使用，以确保部署新合约时包含了所有必要的代码和数据。
      let initCodeSizeWithArgs := add(add(initCodeSize, 0x60), constructorArgsSize)
      // Deploy the contract with the initcode
      //1.create(value, offset, size) 是 EVM 的低级操作码，用于创建新合约：
      // value: 发送到新合约的以太币数量（以 wei 为单位）
      // offset: 内存中初始化代码的起始位置
      // size: 初始化代码的大小（字节数）
      //2.参数解释：
      // 0: 表示不向新合约发送任何以太币
      // initCodePointer: 指向内存中初始化代码的起始位置
      // initCodeSizeWithArgs: 初始化代码加上构造函数参数的总大小
      //3.:= 是 Solidity 内联汇编中的赋值操作符
      //4.hooksInstance: 用于存储新创建的合约地址
      // 这行代码的作用是：
      // 使用内存中从 initCodePointer 开始的 initCodeSizeWithArgs 字节的数据创建一个新合约
      // 不向新合约发送任何以太币
      // 将新创建的合约的地址存储在 hooksInstance 变量中
      //@audit 当使用 CREATE 操作码部署合约时，新合约的地址是基于创建者的地址和 nonce 计算的。
      // 如果发生区块链重组，交易可能会被重新排序或排除，这可能导致 nonce 值发生变化。
      // 结果是，在重组后，相同的交易可能会创建一个具有不同地址的合约。
      hooksInstance := create(0, initCodePointer, initCodeSizeWithArgs)
      if iszero(hooksInstance) {
      //如果部署失败：
      // a. mstore(0x00, 0x30116425):
      // mstore 将一个 32 字节的值存储到内存中。
      // 0x00 是内存中的起始位置。
      // 0x30116425 是 DeploymentFailed() 错误的选择器（函数签名的 keccak256 哈希的前 4 字节）。
      // b. revert(0x1c, 0x04):
      // revert 操作终止执行并恢复状态变更。
      // 0x1c 是内存中错误数据的起始位置（跳过前 28 字节）。
      // 0x04 是要返回的数据长度（4 字节的错误选择器）。
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
    //hooksInstance 是一个地址类型的变量，存储了新创建的钩子合约的地址。
    emit HooksInstanceDeployed(hooksInstance, hooksTemplate);
    getHooksTemplateForInstance[hooksInstance] = hooksTemplate;
  }

  // ========================================================================== //
  //                                   Markets                                  //
  // ========================================================================== //

  /**
   * @dev Get the temporarily stored market parameters for a market that is
   *      currently being deployed.
   */
  /**
 * @dev 获取当前正在部署的市场的临时存储的市场参数。
 */
  function getMarketParameters()
    external
    view
    override
    returns (MarketParameters memory parameters)
  {
    TmpMarketParameterStorage memory tmp = _getTmpMarketParameters();

    parameters.asset = tmp.asset;
    parameters.packedNameWord0 = tmp.packedNameWord0;
    parameters.packedNameWord1 = tmp.packedNameWord1;
    parameters.packedSymbolWord0 = tmp.packedSymbolWord0;
    parameters.packedSymbolWord1 = tmp.packedSymbolWord1;
    parameters.decimals = tmp.decimals;
    parameters.borrower = tmp.borrower;
    parameters.feeRecipient = tmp.feeRecipient;
    parameters.sentinel = sanctionsSentinel;
    parameters.maxTotalSupply = tmp.maxTotalSupply;
    parameters.protocolFeeBips = tmp.protocolFeeBips;
    parameters.annualInterestBips = tmp.annualInterestBips;
    parameters.delinquencyFeeBips = tmp.delinquencyFeeBips;
    parameters.withdrawalBatchDuration = tmp.withdrawalBatchDuration;
    parameters.reserveRatioBips = tmp.reserveRatioBips;
    parameters.delinquencyGracePeriod = tmp.delinquencyGracePeriod;
    parameters.archController = _archController;
    parameters.sphereXEngine = sphereXEngine();
    parameters.hooks = tmp.hooks;
  }

  function computeMarketAddress(bytes32 salt) external view override returns (address) {
    return LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, marketInitCodeHash);
  }

  /**
   * @dev Given a string of at most 63 bytes, produces a packed version with two words,
   *      where the first word contains the length byte and the first 31 bytes of the string,
   *      and the second word contains the second 32 bytes of the string.
   */
  /**
 * @dev 给定一个最多 63 字节的字符串，生成一个由两个字（word）组成的打包版本，
 *      其中第一个字包含长度字节和字符串的前 31 个字节，
 *      第二个字包含字符串的后 32 个字节。
 */
//这种打包方法通常用于优化存储布局，特别是在需要频繁访问字符串数据的情况下。
  function _packString(string memory str) internal pure returns (bytes32 word0, bytes32 word1) {
    //@audit 存在Gas漏洞
    assembly {
      //mload(str) 读取 str 指向的内存位置的前 32 字节。
      // 对于字符串，这正好是存储其长度的位置。
      // 因此，这个操作实际上是获取了字符串的长度。
      let length := mload(str)
      // Equivalent to:
      // if (str.length > 63) revert NameOrSymbolTooLong();
      if gt(length, 0x3f) {
        mstore(0, 0x19a65cb6)
        //字节顺序：
        // 在 32 字节槽中，字节是从左到右排列的。
        // 我们的 4 字节错误选择器占据了最左边的 4 个字节。
        // 计算 0x1c：
        // 32 字节 = 0x20 (十六进制)
        // 4 字节 = 0x04 (十六进制)
        // 0x20 - 0x04 = 0x1c

        //0x1c (28 in decimal) 是内存中错误数据的起始位置。这跳过了 32 字节中的前 28 字节。
        //0x04 (4 in decimal) 是要返回的数据长度，正好是错误选择器的长度。
        //@audit没看懂
        revert(0x1c, 0x04)
      }
      // Load the length and first 31 bytes of the string into the first word
      // by reading from 31 bytes after the length pointer.
      //这行代码的目的是将字符串的长度和前 31 个字节打包到一个 32 字节的 word 中。
      //@audit 没看懂
      //add(str, 0x1f):
      // str 是指向字符串在内存中位置的指针。
      // 0x1f 是十六进制的 31。
      // 这个操作将指针向前移动 31 字节。
      word0 := mload(add(str, 0x1f))
      // If the string is less than 32 bytes, the second word will be zeroed out.
      //0x3f 是十六进制的 63。 0x1f 是十六进制的 31。
      //如果字符串长度 ≤ 31，word1 将为 0。
      //如果字符串长度 > 31，word1 将包含字符串的后半部分。
      word1 := mul(mload(add(str, 0x3f)), gt(mload(str), 0x1f))
    }
  }

  function _deployMarket(
    DeployMarketInputs memory parameters,
    bytes memory hooksData,
    address hooksTemplate,
    HooksTemplate memory templateDetails,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) internal returns (address market) {
    if (IWildcatArchController(_archController).isBlacklistedAsset(parameters.asset)) {
      revert AssetBlacklisted();
    }
    //从 HooksConfig 类型中提取 hooks 合约地址的操作
    address hooksInstance = parameters.hooks.hooksAddress();
    //address(bytes20(salt)) == msg.sender: 检查 salt 的前 20 字节是否等于调用者的地址。
    // bytes20(salt) == bytes20(0): 检查 salt 的前 20 字节是否全为 0。
    // 如果这两个条件都不满足，函数会 revert 并抛出 SaltDoesNotContainSender() 错误。
    //NOT (condition1 OR condition2)
    //如果 salt 的前 20 字节既不等于 msg.sender，也不全为 0，则整个表达式为 true。
    if (!(address(bytes20(salt)) == msg.sender || bytes20(salt) == bytes20(0))) {
      revert SaltDoesNotContainSender();
    }

    if (
      originationFeeAsset != templateDetails.originationFeeAsset ||
      originationFeeAmount != templateDetails.originationFeeAmount
    ) {
      revert FeeMismatch();
    }
    //收取发起费用：当创建新市场或执行某些操作时，收取预定义的费用。
    if (originationFeeAsset != address(0)) {
      originationFeeAsset.safeTransferFrom(
        msg.sender,
        templateDetails.feeRecipient,
        originationFeeAmount
      );
    }

    market = LibStoredInitCode.calculateCreate2Address(ownCreate2Prefix, salt, marketInitCodeHash);

    parameters.hooks = IHooks(hooksInstance).onCreateMarket(
      msg.sender,
      market,
      parameters,
      hooksData
    );
    uint8 decimals = parameters.asset.decimals();

    string memory name = string.concat(parameters.namePrefix, parameters.asset.name());
    string memory symbol = string.concat(parameters.symbolPrefix, parameters.asset.symbol());

    TmpMarketParameterStorage memory tmp = TmpMarketParameterStorage({
      borrower: msg.sender,
      asset: parameters.asset,
      packedNameWord0: bytes32(0),
      packedNameWord1: bytes32(0),
      packedSymbolWord0: bytes32(0),
      packedSymbolWord1: bytes32(0),
      decimals: decimals,
      feeRecipient: templateDetails.feeRecipient,
      protocolFeeBips: templateDetails.protocolFeeBips,
      maxTotalSupply: parameters.maxTotalSupply,
      annualInterestBips: parameters.annualInterestBips,
      delinquencyFeeBips: parameters.delinquencyFeeBips,
      withdrawalBatchDuration: parameters.withdrawalBatchDuration,
      reserveRatioBips: parameters.reserveRatioBips,
      delinquencyGracePeriod: parameters.delinquencyGracePeriod,
      hooks: parameters.hooks
    });
    {
      (tmp.packedNameWord0, tmp.packedNameWord1) = _packString(name);
      (tmp.packedSymbolWord0, tmp.packedSymbolWord1) = _packString(symbol);
    }

    _setTmpMarketParameters(tmp);

    if (market.code.length != 0) {
      revert MarketAlreadyExists();
    }
    LibStoredInitCode.create2WithStoredInitCode(marketInitCodeStorage, salt);

    IWildcatArchController(_archController).registerMarket(market);

    _tmpMarketParameters.setEmpty();

    _marketsByHooksTemplate[hooksTemplate].push(market);

    emit MarketDeployed(
      hooksTemplate,
      market,
      name,
      symbol,
      tmp.asset,
      tmp.maxTotalSupply,
      tmp.annualInterestBips,
      tmp.delinquencyFeeBips,
      tmp.withdrawalBatchDuration,
      tmp.reserveRatioBips,
      tmp.delinquencyGracePeriod,
      tmp.hooks
    );
  }

  function deployMarket(
    DeployMarketInputs calldata parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external override nonReentrant returns (address market) {
    if (!IWildcatArchController(_archController).isRegisteredBorrower(msg.sender)) {
      revert NotApprovedBorrower();
    }
    address hooksInstance = parameters.hooks.hooksAddress();
    address hooksTemplate = getHooksTemplateForInstance[hooksInstance];
    if (hooksTemplate == address(0)) {
      revert HooksInstanceNotFound();
    }
    HooksTemplate memory templateDetails = _templateDetails[hooksTemplate];
    market = _deployMarket(
      parameters,
      hooksData,
      hooksTemplate,
      templateDetails,
      salt,
      originationFeeAsset,
      originationFeeAmount
    );
  }

  function deployMarketAndHooks(
    address hooksTemplate,
    bytes calldata hooksTemplateArgs,
    DeployMarketInputs memory parameters,
    bytes calldata hooksData,
    bytes32 salt,
    address originationFeeAsset,
    uint256 originationFeeAmount
  ) external override nonReentrant returns (address market, address hooksInstance) {
    if (!IWildcatArchController(_archController).isRegisteredBorrower(msg.sender)) {
      revert NotApprovedBorrower();
    }
    HooksTemplate memory templateDetails = _templateDetails[hooksTemplate];
    if (!templateDetails.exists) {
      revert HooksTemplateNotFound();
    }
    hooksInstance = _deployHooksInstance(hooksTemplate, hooksTemplateArgs);
    parameters.hooks = parameters.hooks.setHooksAddress(hooksInstance);
    market = _deployMarket(
      parameters,
      hooksData,
      hooksTemplate,
      templateDetails,
      salt,
      originationFeeAsset,
      originationFeeAmount
    );
  }

  /**
   * @dev Push any changes to the fee configuration of `hooksTemplate` to markets
   *      using any instances of that template at `_marketsByHooksTemplate[hooksTemplate]`.
   *      Starts at `marketStartIndex` and ends one before `marketEndIndex`  or markets.length,
   *      whichever is lowest.
   */
  function pushProtocolFeeBipsUpdates(
    address hooksTemplate,
    uint marketStartIndex,
    uint marketEndIndex
  ) public override nonReentrant {
    HooksTemplate memory details = _templateDetails[hooksTemplate];
    if (!details.exists) revert HooksTemplateNotFound();

    address[] storage markets = _marketsByHooksTemplate[hooksTemplate];
    marketEndIndex = MathUtils.min(marketEndIndex, markets.length);
    uint256 count = marketEndIndex - marketStartIndex;
    uint256 setProtocolFeeBipsCalldataPointer;
    uint16 protocolFeeBips = details.protocolFeeBips;
    assembly {
      // Write the calldata for `market.setProtocolFeeBips(protocolFeeBips)`
      // this will be reused for every market
      setProtocolFeeBipsCalldataPointer := mload(0x40)
      mstore(0x40, add(setProtocolFeeBipsCalldataPointer, 0x40))
      // Write selector for `setProtocolFeeBips(uint16)`
      mstore(setProtocolFeeBipsCalldataPointer, 0xae6ea191)
      mstore(add(setProtocolFeeBipsCalldataPointer, 0x20), protocolFeeBips)
      // Add 28 bytes to get the exact pointer to the first byte of the selector
      setProtocolFeeBipsCalldataPointer := add(setProtocolFeeBipsCalldataPointer, 0x1c)
    }
    for (uint256 i = 0; i < count; i++) {
      address market = markets[marketStartIndex + i];
      assembly {
        if iszero(call(gas(), market, 0, setProtocolFeeBipsCalldataPointer, 0x24, 0, 0)) {
          // Equivalent to `revert SetProtocolFeeBipsFailed()`
          mstore(0, 0x4484a4a9)
          revert(0x1c, 0x04)
        }
      }
    }
  }


  /**
   * @dev Push any changes to the fee configuration of `hooksTemplate` to all markets
   *      using any instances of that template at `_marketsByHooksTemplate[hooksTemplate]`.
   */
  function pushProtocolFeeBipsUpdates(address hooksTemplate) external {
    pushProtocolFeeBipsUpdates(hooksTemplate, 0, type(uint256).max);
  }
}
