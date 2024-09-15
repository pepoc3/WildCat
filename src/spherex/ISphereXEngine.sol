// SPDX-License-Identifier: UNLICENSED
// (c) SphereX 2023 Terms&Conditions
pragma solidity ^0.8.20;

/// @dev this struct is used to reduce the stack usage of the modifiers.
struct ModifierLocals {
  bytes32[] storageSlots;
  bytes32[] valuesBefore;
  uint256 gas;
  address engine;
}

/// @title Interface for SphereXEngine - definitions of core functionality
/// @author SphereX Technologies ltd
/// @notice This interface is imported by SphereXProtected, so that SphereXProtected can call functions from SphereXEngine
/// @dev Full docs of these functions can be found in SphereXEngine
/// @title SphereXEngine 接口 - 核心功能的定义
/// @author SphereX Technologies ltd
/// @notice 此接口被 SphereXProtected 导入，以便 SphereXProtected 可以调用 SphereXEngine 中的函数
/// @dev 这些函数的完整文档可以在 SphereXEngine 中找到
interface ISphereXEngine {
  function sphereXValidatePre(
    int256 num,
    address sender,
    bytes calldata data
  ) external returns (bytes32[] memory);

  function sphereXValidatePost(
    int256 num,
    uint256 gas,
    bytes32[] calldata valuesBefore,
    bytes32[] calldata valuesAfter
  ) external;

  function sphereXValidateInternalPre(int256 num) external returns (bytes32[] memory);

  function sphereXValidateInternalPost(
    int256 num,
    uint256 gas,
    bytes32[] calldata valuesBefore,
    bytes32[] calldata valuesAfter
  ) external;

  function addAllowedSenderOnChain(address sender) external;

  /// This function is taken as is from OZ IERC165, we don't inherit from OZ
  /// to avoid collisions with the customer OZ version.
  /// @dev Returns true if this contract implements the interface defined by
  /// `interfaceId`. See the corresponding
  /// https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
  /// to learn more about how these ids are created.
  /// This function call must use less than 30 000 gas.
  function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
