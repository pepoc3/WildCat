// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.24;

library LibStoredInitCode {
  error InitCodeDeploymentFailed();
  error DeploymentFailed();

  function deployInitCode(bytes memory data) internal returns (address initCodeStorage) {
    assembly {
      let size := mload(data)
      let createSize := add(size, 0x0b)
      // Prefix Code
      //
      // Has trailing STOP instruction so the deployed data
      // can not be executed as a smart contract.
      //
      // Instruction                | Stack
      // ----------------------------------------------------
      // PUSH2 size                 | size                  |
      // PUSH0                      | 0, size               |
      // DUP2                       | size, 0, size         |
      // PUSH1 10 (offset to STOP)  | 10, size, 0, size     |
      // PUSH0                      | 0, 10, size, 0, size  |
      // CODECOPY                   | 0, size               |
      // RETURN                     |                       |
      // STOP                       |                       |
      // ----------------------------------------------------

      // Shift (size + 1) to position it in front of the PUSH2 instruction.
      // Reuse `data.length` memory for the create prefix to avoid
      // unnecessary memory allocation.
      mstore(data, or(shl(64, add(size, 1)), 0x6100005f81600a5f39f300))
      // Deploy the code storage
      initCodeStorage := create(0, add(data, 21), createSize)
      // if (initCodeStorage == address(0)) revert InitCodeDeploymentFailed();
      if iszero(initCodeStorage) {
        mstore(0, 0x11c8c3c0)
        revert(0x1c, 0x04)
      }
      // Restore `data.length`
      mstore(data, size)
    }
  }

  /**
   * @dev Returns the create2 prefix for a given deployer address.
   *      Equivalent to `uint256(uint160(deployer)) | (0xff << 160)`
   */
  /**
 * @dev 返回给定部署者地址的 create2 前缀。
 *      等价于 `uint256(uint160(deployer)) | (0xff << 160)`
 */
  function getCreate2Prefix(address deployer) internal pure returns (uint256 create2Prefix) {
    assembly {
      // 1. deployer: 这是部署者的地址。在 EVM 中，地址是 20 字节（160 位）长。
      // 2. 0xff0000000000000000000000000000000000000000:
      //   这是一个 32 字节（256 位）的值。
      //   最左边的字节是 0xff，后面跟着 20 字节的零。
      //   操作的效果：
      //   deployer 地址占据结果的低 160 位。
      //   0xff 被放置在结果的第 161-168 位（从右数第 21 个字节）。
      //   剩余的高位都是 0。

      //低 20 字节是部署者地址
      //第 21 个字节是 0xff
      //高 11 字节是零
      create2Prefix := or(deployer, 0xff0000000000000000000000000000000000000000)
    }
  }

  function calculateCreate2Address(
    uint256 create2Prefix,
    bytes32 salt,
    uint256 initCodeHash
  ) internal pure returns (address create2Address) {
    assembly {
      // Cache the free memory pointer so it can be restored at the end
      //缓存自由内存指针，以便在最后恢复
      let freeMemoryPointer := mload(0x40)

      // Write 0xff + address to bytes 11:32
      //0xff + address" 是指我们要写入的具体内容：
      // 0xff 是一个字节，在 CREATE2 操作中用作前缀。
      // address 是部署者的地址（20字节）。
      // "to bytes 11:32" 指定了这些数据在 32 字节内存槽中的位置：
      // 字节 0-10 保持为零（共11字节）
      // 字节 11 是 0xff
      // 字节 12-31 是地址（20字节）
      mstore(0x00, create2Prefix)

      // Write salt to bytes 32:64
      //0x20 是十六进制的 32，表示内存中的起始位置。这正好是第二个 32 字节槽的开始。
      // salt 是要存储的值，通常是一个 32 字节的值。
      mstore(0x20, salt)

      // Write initcode hash to bytes 64:96
      mstore(0x40, initCodeHash)

      // Calculate create2 address

      //CREATE2 地址计算公式：
      // 根据 EIP-1014，CREATE2 地址的计算公式是：
      // keccak256( 0xff ++ address ++ salt ++ keccak256(init_code))[12:]
      // 2. 内存布局：
      // 字节 0-10：11 个零字节
      // 字节 11：0xff
      // 字节 12-31：部署者地址（20字节）
      // 字节 32-63：salt（32字节）
      // 字节 64-95：init_code 的 keccak256 哈希（32字节）

      //keccak256(0x0b, 0x55):
      // keccak256 是一个哈希函数，用于计算输入数据的哈希值。
      // 0x0b (11 in decimal) 是内存中开始读取数据的位置。这跳过了前面 11 个字节的零值。
      // 0x55 (85 in decimal) 是要读取的字节数。这包括了之前存储的所有数据（0xff + address + salt + initcode hash）。
      // and(..., 0xffffffffffffffffffffffffffffffffffffffff):
      // and 是位运算中的与操作。
      // 0xffffffffffffffffffffffffffffffffffffffff 是一个 20 字节（160 位）的掩码。
      // 这个操作将哈希结果截断为 20 字节，因为以太坊地址是 20 字节长。
      create2Address := and(keccak256(0x0b, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)

      // Restore the free memory pointer
      mstore(0x40, freeMemoryPointer)
    }
  }

  function createWithStoredInitCode(address initCodeStorage) internal returns (address deployment) {
    deployment = createWithStoredInitCode(initCodeStorage, 0);
  }

  function createWithStoredInitCode(
    address initCodeStorage,
    uint256 value
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      deployment := create(value, initCodePointer, initCodeSize)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt
  ) internal returns (address deployment) {
    deployment = create2WithStoredInitCode(initCodeStorage, salt, 0);
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      deployment := create2(value, initCodePointer, initCodeSize, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    uint256 value,
    bytes memory constructorArgs
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      // Copy code from target address to memory starting at byte 1
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      // Copy constructor args from memory to initcode
      let constructorArgsSize := mload(constructorArgs)
      mcopy(add(initCodePointer, initCodeSize), add(constructorArgs, 0x20), constructorArgsSize)
      let initCodeSizeWithArgs := add(initCodeSize, constructorArgsSize)
      deployment := create2(value, initCodePointer, initCodeSizeWithArgs, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  function create2WithStoredInitCode(
    address initCodeStorage,
    bytes32 salt,
    bytes memory constructorArgs
  ) internal returns (address deployment) {
    return create2WithStoredInitCode(initCodeStorage, salt, 0, constructorArgs);
  }

  function create2WithStoredInitCodeCD(
    address initCodeStorage,
    bytes32 salt,
    uint256 value,
    bytes calldata constructorArgs
  ) internal returns (address deployment) {
    assembly {
      let initCodePointer := mload(0x40)
      let initCodeSize := sub(extcodesize(initCodeStorage), 1)
      // Copy code from target address to memory starting at byte 1
      extcodecopy(initCodeStorage, initCodePointer, 1, initCodeSize)
      // Copy constructor args from calldata to end of initcode
      let constructorArgsSize := constructorArgs.length
      calldatacopy(add(initCodePointer, initCodeSize), constructorArgs.offset, constructorArgsSize)
      let initCodeSizeWithArgs := add(initCodeSize, constructorArgsSize)
      deployment := create2(value, initCodePointer, initCodeSizeWithArgs, salt)
      if iszero(deployment) {
        mstore(0x00, 0x30116425) // DeploymentFailed()
        revert(0x1c, 0x04)
      }
    }
  }

  function create2WithStoredInitCodeCD(
    address initCodeStorage,
    bytes32 salt,
    bytes calldata constructorArgs
  ) internal returns (address deployment) {
    return create2WithStoredInitCodeCD(initCodeStorage, salt, 0, constructorArgs);
  }
}
