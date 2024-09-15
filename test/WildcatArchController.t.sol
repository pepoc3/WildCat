// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

import 'forge-std/Test.sol';
import 'sol-utils/test/Prankster.sol';
import 'src/WildcatArchController.sol';

contract WildcatArchControllerTest is Test, Prankster {
  event MarketAdded(address indexed controller, address market);
  event MarketRemoved(address market);

  event ControllerFactoryAdded(address controllerFactory);
  event ControllerFactoryRemoved(address controllerFactory);

  event BorrowerAdded(address borrower);
  event BorrowerRemoved(address borrower);

  event ControllerAdded(address indexed controllerFactory, address controller);
  event ControllerRemoved(address controller);

  event AssetBlacklisted(address asset);
  event AssetPermitted(address asset);

  WildcatArchController internal archController;
  address internal constant controllerFactory = address(1);
  address internal constant controller = address(2);
  address internal constant borrower = address(3);
  address internal constant market = address(4);

  address internal constant controllerFactory2 = address(5);
  address internal constant controller2 = address(6);
  address internal constant borrower2 = address(7);
  address internal constant market2 = address(8);
  //@audit 测试函数新增
  address public owner = address(0x1234567890123456789012345678901234567890);

  function setUp() external {
    archController = new WildcatArchController();
  }

  function _registerController(address _controllerFactory, address _controller) internal {
    if (!archController.isRegisteredControllerFactory(_controllerFactory)) {
      archController.registerControllerFactory(_controllerFactory);
    }
    vm.prank(_controllerFactory);
    archController.registerController(_controller);
  }

  function _registerMarket(
    address _controllerFactory,
    address _controller,
    address _market
  ) internal {
    if (!archController.isRegisteredController(_controller)) {
      _registerController(_controllerFactory, _controller);
    }
    vm.prank(_controller);
    archController.registerMarket(_market);
  }

  /* -------------------------------------------------------------------------- */
  /*                                 Controller                                 */
  /* -------------------------------------------------------------------------- */

  function test_registerController() external {
    archController.registerControllerFactory(controllerFactory);

    vm.expectEmit(address(archController));
    emit ControllerAdded(controllerFactory, controller);

    vm.prank(controllerFactory);
    archController.registerController(controller);
  }

  function test_registerController_NotControllerFactory(address controller) external {
    vm.expectRevert(WildcatArchController.NotControllerFactory.selector);
    archController.registerController(controller);
  }

  function test_registerController_ControllerAlreadyExists() external {
    _registerController(controllerFactory, controller);
    vm.expectRevert(WildcatArchController.ControllerAlreadyExists.selector);
    vm.prank(controllerFactory);
    archController.registerController(controller);
  }

  function test_removeController() external {
    _registerController(controllerFactory, controller);
    vm.expectEmit(address(archController));
    emit ControllerRemoved(controller);
    archController.removeController(controller);
  }

  function test_removeController_ControllerDoesNotExist() external {
    vm.expectRevert(WildcatArchController.ControllerDoesNotExist.selector);
    archController.removeController(controller);
  }

  function test_removeController_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.removeController(controller);
  }

  function test_isRegisteredController() external returns (bool) {
    assertFalse(archController.isRegisteredController(controller));
    _registerController(controllerFactory, controller);
    _registerController(controllerFactory, controller2);
    assertTrue(archController.isRegisteredController(controller));
    assertTrue(archController.isRegisteredController(controller2));
    archController.removeController(controller);
    assertFalse(archController.isRegisteredController(controller));
  }

  function test_getRegisteredControllers() external returns (address[] memory) {
    _registerController(controllerFactory, controller);
    vm.prank(controllerFactory);
    archController.registerController(controller2);
    address[] memory controllers = archController.getRegisteredControllers();
    assertEq(controllers.length, 2);
    assertEq(controllers[0], controller);
    assertEq(controllers[1], controller2);
    controllers = archController.getRegisteredControllers(0, 3);
    assertEq(controllers.length, 2);
    assertEq(controllers[0], controller);
    assertEq(controllers[1], controller2);
    controllers = archController.getRegisteredControllers(1, 2);
    assertEq(controllers.length, 1);
    assertEq(controllers[0], controller2);
    assertEq(archController.getRegisteredControllersCount(), 2);
  }

  /* -------------------------------------------------------------------------- */
  /*                                    Market                                   */
  /* -------------------------------------------------------------------------- */

  function test_registerMarket() external {
    _registerController(controllerFactory, controller);

    vm.expectEmit(address(archController));
    emit MarketAdded(controller, market);

    vm.prank(controller);
    archController.registerMarket(market);
  }

  function test_registerMarket_NotController(address controller) external {
    vm.expectRevert(WildcatArchController.NotController.selector);
    archController.registerMarket(controller);
  }

  function test_registerMarket_MarketAlreadyExists() external {
    _registerMarket(controllerFactory, controller, market);
    vm.expectRevert(WildcatArchController.MarketAlreadyExists.selector);
    vm.prank(controller);
    archController.registerMarket(market);
  }

  function test_removeMarket() external {
    _registerMarket(controllerFactory, controller, market);
    vm.expectEmit(address(archController));
    emit MarketRemoved(market);
    archController.removeMarket(market);
  }

  function test_removeMarket_MarketDoesNotExist() external {
    vm.expectRevert(WildcatArchController.MarketDoesNotExist.selector);
    archController.removeMarket(market);
  }

  function test_removeMarket_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.removeMarket(market);
  }

  function test_isRegisteredMarket() external returns (bool) {
    assertFalse(archController.isRegisteredMarket(market));
    _registerMarket(controllerFactory, controller, market);
    assertTrue(archController.isRegisteredMarket(market));
    archController.removeMarket(market);
    assertFalse(archController.isRegisteredMarket(market));
  }

  function test_getRegisteredMarkets() external returns (address[] memory) {
    _registerMarket(controllerFactory, controller, market);
    _registerMarket(controllerFactory, controller, market2);
    address[] memory markets = archController.getRegisteredMarkets();
    assertEq(markets.length, 2);
    assertEq(markets[0], market);
    assertEq(markets[1], market2);
    markets = archController.getRegisteredMarkets(0, 3);
    assertEq(markets.length, 2);
    assertEq(markets[0], market);
    assertEq(markets[1], market2);
    markets = archController.getRegisteredMarkets(1, 2);
    assertEq(markets.length, 1);
    assertEq(markets[0], market2);
    assertEq(archController.getRegisteredMarketsCount(), 2);
    archController.removeMarket(market);
    markets = archController.getRegisteredMarkets();
    assertEq(markets.length, 1);
    assertEq(markets[0], market2);
    assertEq(archController.getRegisteredMarketsCount(), 1);
  }

  /* -------------------------------------------------------------------------- */
  /*                                  Borrowers                                 */
  /* -------------------------------------------------------------------------- */

  function test_registerBorrower() external {
    vm.expectEmit(address(archController));
    emit BorrowerAdded(borrower);

    archController.registerBorrower(borrower);
  }

  function test_registerBorrower_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.registerBorrower(borrower);
  }

  function test_registerBorrower_BorrowerAlreadyExists() external {
    archController.registerBorrower(borrower);
    vm.expectRevert(WildcatArchController.BorrowerAlreadyExists.selector);
    archController.registerBorrower(borrower);
  }

  function test_registerBorrower_GasLimitConcern() external {
    uint256 initialGas = gasleft();
    uint256 gasUsed;
    uint256 totalGasUsed = 0;
    uint256 borrowerCount = 0;
    address[] memory borrowers = new address[](1000); // 预先创建 1000 个不同的地址

    for (uint256 i = 0; i < 100; i++) {
        borrowers[i] = address(uint160(i + 1)); // 创建唯一地址
    }

    for (uint256 i = 0; i < 100; i++) {
        uint256 gasBeforeRegister = gasleft();
        archController.registerBorrower(borrowers[i]);
        gasUsed = gasBeforeRegister - gasleft();
        totalGasUsed += gasUsed;
        borrowerCount++;
        //1000：47090414   100：4734614
        // if (i % 100 == 0) {
        //     console.log("Borrowers registered: %s, Last operation gas used: %s, Total gas used: %s", borrowerCount, gasUsed, totalGasUsed);
        // }

        // if (totalGasUsed > 30_000_000) { // 假设区块 gas 限制为 30M
        //     console.log("Gas limit concern: Reached high gas usage at %s borrowers", borrowerCount);
        //     break;
        // }
    }

    console.log("Final borrower count: %s, Total gas used: %s", borrowerCount, totalGasUsed);
    // assert(borrowerCount > 0, "Should be able to register at least one borrower");
}


// 在 WildcatArchControllerTest 合约中添加这个新的测试函数

function testDOS_SlowDownOtherTransactions() public {
    // 首先，注册大量借款人来模拟攻击者行为
    for (uint256 i = 0; i < 1000; i++) {
        vm.prank(owner);
        archController.registerBorrower(address(uint160(i + 1000)));
    }

    // 记录正常用户操作的初始 gas 成本
    uint256 initialGas = gasleft();
    vm.prank(owner);
    archController.registerBorrower(address(1));
    uint256 initialGasUsed = initialGas - gasleft();

    // 继续注册更多借款人，进一步增加状态复杂度
    for (uint256 i = 0; i < 1000; i++) {
        vm.prank(owner);
        archController.registerBorrower(address(uint160(i + 2000)));
    }

    // 再次测量正常用户操作的 gas 成本
    uint256 finalGas = gasleft();
    vm.prank(owner);
    archController.registerBorrower(address(2));
    uint256 finalGasUsed = finalGas - gasleft();

    // 输出 gas 使用情况
    console.log("Initial gas used for normal operation:", initialGasUsed);
    console.log("Final gas used for normal operation:", finalGasUsed);
    
    // 检查 gas 使用是否显著增加
    assertTrue(finalGasUsed > initialGasUsed * 2, "Gas usage should increase significantly");

    // 尝试模拟区块 gas 限制
    uint256 blockGasLimit = 30000000; // 假设的区块 gas 限制
    vm.prank(owner);
    uint256 gasLeft = gasleft();
    bool success = true;
    try archController.registerBorrower(address(3)) {
        uint256 gasUsed = gasLeft - gasleft();
        success = gasUsed <= blockGasLimit;
    } catch {
        success = false;
    }
    
    // 检查是否由于 gas 限制而无法执行正常操作
    assertFalse(success, "Normal operation should fail due to gas limit");
}

  function test_removeBorrower() external {
    archController.registerBorrower(borrower);
    vm.expectEmit(address(archController));
    emit BorrowerRemoved(borrower);
    archController.removeBorrower(borrower);
  }

  function test_removeBorrower_BorrowerDoesNotExist() external {
    vm.expectRevert(WildcatArchController.BorrowerDoesNotExist.selector);
    archController.removeBorrower(borrower);
  }

  function test_removeBorrower_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.removeBorrower(borrower);
  }

  function test_isRegisteredBorrower() external returns (bool) {
    assertFalse(archController.isRegisteredBorrower(borrower));
    archController.registerBorrower(borrower);
    assertTrue(archController.isRegisteredBorrower(borrower));
    archController.removeBorrower(borrower);
    assertFalse(archController.isRegisteredBorrower(borrower));
  }

  function test_getRegisteredBorrowers() external returns (address[] memory) {
    archController.registerBorrower(borrower);
    archController.registerBorrower(borrower2);

    address[] memory borrowers = archController.getRegisteredBorrowers();
    assertEq(borrowers.length, 2);
    assertEq(borrowers[0], borrower);
    assertEq(borrowers[1], borrower2);

    borrowers = archController.getRegisteredBorrowers(0, 3);
    assertEq(borrowers.length, 2);
    assertEq(borrowers[0], borrower);
    assertEq(borrowers[1], borrower2);

    borrowers = archController.getRegisteredBorrowers(1, 2);
    assertEq(borrowers.length, 1);
    assertEq(borrowers[0], borrower2);
    assertEq(archController.getRegisteredBorrowersCount(), 2);

    archController.removeBorrower(borrower);
    borrowers = archController.getRegisteredBorrowers();
    assertEq(borrowers.length, 1);
    assertEq(borrowers[0], borrower2);
    assertEq(archController.getRegisteredBorrowersCount(), 1);
  }


function test_getRegisteredBorrowers_IntegerUnderflow() external {
  // Register some borrowers
  archController.registerBorrower(borrower);
  archController.registerBorrower(borrower2);

  // Test case 1: start > end
  vm.expectRevert();
  archController.getRegisteredBorrowers(2, 1);

  // Test case 2: start >= len
  vm.expectRevert();
  archController.getRegisteredBorrowers(3, 4);

  // Test case 3: end > len
  address[] memory borrowers = archController.getRegisteredBorrowers(0, 5);
  assertEq(borrowers.length, 2);
  assertEq(borrowers[0], borrower);
  assertEq(borrowers[1], borrower2);

  // Test case 4: start == end
  borrowers = archController.getRegisteredBorrowers(1, 1);
  assertEq(borrowers.length, 0);
}


function testDOS_GetRegisteredBorrowers() public {
    // 首先，注册大量借款人来模拟攻击者行为
    for (uint256 i = 0; i < 1000; i++) {
        archController.registerBorrower(address(uint160(i + 1000)));
    }

    // 记录获取所有借款人的初始 gas 成本
    uint256 initialGas = gasleft();
    archController.getRegisteredBorrowers();
    uint256 initialGasUsed = initialGas - gasleft();

    // 继续注册更多借款人，进一步增加状态复杂度
    for (uint256 i = 0; i < 1000; i++) {
        archController.registerBorrower(address(uint160(i + 2000)));
    }

    // 再次测量获取所有借款人的 gas 成本
    uint256 finalGas = gasleft();
    archController.getRegisteredBorrowers();
    uint256 finalGasUsed = finalGas - gasleft();

    // 输出 gas 使用情况
    console.log("Initial gas used for getRegisteredBorrowers:", initialGasUsed);
    console.log("Final gas used for getRegisteredBorrowers:", finalGasUsed);
    
    // 检查 gas 使用是否显著增加
    assertTrue(finalGasUsed > initialGasUsed * 2, "Gas usage should increase significantly");

    // 尝试模拟区块 gas 限制
    // uint256 blockGasLimit = 30000000; // 假设的区块 gas 限制
    // uint256 gasLeft = gasleft();
    // bool success = true;
    // try archController.getRegisteredBorrowers() {
    //     uint256 gasUsed = gasLeft - gasleft();
    //     success = gasUsed <= blockGasLimit;
    // } catch {
    //     success = false;
    // }
    
    // // 检查是否由于 gas 限制而无法执行 getRegisteredBorrowers
    // assertFalse(success, "getRegisteredBorrowers should fail due to gas limit");
}




  // ========================================================================== //
  //                                  Blacklist                                 //
  // ========================================================================== //

  function test_addBlacklist() external {
    vm.expectEmit(address(archController));
    emit AssetBlacklisted(borrower);

    archController.addBlacklist(borrower);
  }

  function test_addBlacklist_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.addBlacklist(borrower);
  }

  function test_addBlacklist_AssetAlreadyBlacklisted() external {
    archController.addBlacklist(borrower);
    vm.expectRevert(WildcatArchController.AssetAlreadyBlacklisted.selector);
    archController.addBlacklist(borrower);
  }

  function test_removeBlacklist() external {
    archController.addBlacklist(borrower);
    vm.expectEmit(address(archController));
    emit AssetPermitted(borrower);
    archController.removeBlacklist(borrower);
  }

  function test_removeBlacklist_AssetNotBlacklisted() external {
    vm.expectRevert(WildcatArchController.AssetNotBlacklisted.selector);
    archController.removeBlacklist(borrower);
  }

  function test_removeBlacklist_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.removeBlacklist(borrower);
  }

  function test_isBlacklistedAsset() external returns (bool) {
    assertFalse(archController.isBlacklistedAsset(borrower));
    archController.addBlacklist(borrower);
    assertTrue(archController.isBlacklistedAsset(borrower));
    archController.removeBlacklist(borrower);
    assertFalse(archController.isBlacklistedAsset(borrower));
  }

  function test_getBlacklistedAssets() external returns (address[] memory) {
    archController.addBlacklist(borrower);
    archController.addBlacklist(borrower2);

    address[] memory blackListedAssets = archController.getBlacklistedAssets();
    assertEq(blackListedAssets.length, 2);
    assertEq(blackListedAssets[0], borrower);
    assertEq(blackListedAssets[1], borrower2);

    blackListedAssets = archController.getBlacklistedAssets(0, 3);
    assertEq(blackListedAssets.length, 2);
    assertEq(blackListedAssets[0], borrower);
    assertEq(blackListedAssets[1], borrower2);

    blackListedAssets = archController.getBlacklistedAssets(1, 2);
    assertEq(blackListedAssets.length, 1);
    assertEq(blackListedAssets[0], borrower2);
    assertEq(archController.getBlacklistedAssetsCount(), 2);

    archController.removeBlacklist(borrower);
    blackListedAssets = archController.getBlacklistedAssets();
    assertEq(blackListedAssets.length, 1);
    assertEq(blackListedAssets[0], borrower2);
    assertEq(archController.getBlacklistedAssetsCount(), 1);
  }

  /* -------------------------------------------------------------------------- */
  /*                            Controller Factories                            */
  /* -------------------------------------------------------------------------- */
  function test_registerControllerFactory() external {
    vm.expectEmit(address(archController));
    emit ControllerFactoryAdded(controllerFactory);

    archController.registerControllerFactory(controllerFactory);
  }

  function test_registerControllerFactory_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.registerControllerFactory(controllerFactory);
  }

  function test_registerControllerFactory_ControllerFactoryAlreadyExists() external {
    archController.registerControllerFactory(controllerFactory);
    vm.expectRevert(WildcatArchController.ControllerFactoryAlreadyExists.selector);
    archController.registerControllerFactory(controllerFactory);
  }

  function test_removeControllerFactory() external {
    archController.registerControllerFactory(controllerFactory);
    vm.expectEmit(address(archController));
    emit ControllerFactoryRemoved(controllerFactory);
    archController.removeControllerFactory(controllerFactory);
  }

  function test_removeControllerFactory_ControllerFactoryDoesNotExist() external {
    vm.expectRevert(WildcatArchController.ControllerFactoryDoesNotExist.selector);
    archController.removeControllerFactory(controllerFactory);
  }

  function test_removeControllerFactory_Unauthorized() external {
    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(controllerFactory);
    archController.removeControllerFactory(controllerFactory);
  }

  function test_isRegisteredControllerFactory() external returns (bool) {
    assertFalse(archController.isRegisteredControllerFactory(controllerFactory));
    archController.registerControllerFactory(controllerFactory);
    assertTrue(archController.isRegisteredControllerFactory(controllerFactory));
    archController.removeControllerFactory(controllerFactory);
    assertFalse(archController.isRegisteredControllerFactory(controllerFactory));
  }

  function test_getRegisteredControllerFactories() external returns (address[] memory) {
    archController.registerControllerFactory(controllerFactory);
    archController.registerControllerFactory(controllerFactory2);

    address[] memory controllerFactories = archController.getRegisteredControllerFactories();
    assertEq(controllerFactories.length, 2);
    assertEq(controllerFactories[0], controllerFactory);
    assertEq(controllerFactories[1], controllerFactory2);

    controllerFactories = archController.getRegisteredControllerFactories(0, 3);
    assertEq(controllerFactories.length, 2);
    assertEq(controllerFactories[0], controllerFactory);
    assertEq(controllerFactories[1], controllerFactory2);

    controllerFactories = archController.getRegisteredControllerFactories(1, 2);
    assertEq(controllerFactories.length, 1);
    assertEq(controllerFactories[0], controllerFactory2);
    assertEq(archController.getRegisteredControllerFactoriesCount(), 2);

    archController.removeControllerFactory(controllerFactory);
    controllerFactories = archController.getRegisteredControllerFactories();
    assertEq(controllerFactories.length, 1);
    assertEq(controllerFactories[0], controllerFactory2);
    assertEq(archController.getRegisteredControllerFactoriesCount(), 1);
  }
}
