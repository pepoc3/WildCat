// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;
import { Panic_ErrorSelector, Panic_ErrorCodePointer, Panic_InvalidStorageByteArray, Error_SelectorPointer, Panic_ErrorLength } from '../libraries/Errors.sol';

type TransientBytesArray is uint256;

using LibTransientBytesArray for TransientBytesArray global;

library LibTransientBytesArray {
  /**
   * @dev Decode a dynamic bytes array from transient storage.
   * @param transientSlot Slot for the dynamic bytes array in transient storage
   * @param memoryPointer Pointer to the memory location to write the decoded array to
   * @return endPointer Pointer to the end of the decoded array
   */
  /**
 * @dev 从瞬态存储中解码动态字节数组。
 * //瞬态存储（Transient Storage）是以太坊中的一个相对较新的概念，它在 EIP-1153 中被提出并实现。以下是瞬态存储的主要特点和用途：
    // 1. 定义：
    // 瞬态存储是一种临时的数据存储机制，数据只在单个交易的执行期间存在。
    // 生命周期：
    // 数据在交易开始时被初始化为零。
    // 数据可以在交易执行过程中被读取和修改。
    // 数据在交易结束时被丢弃，不会持久化到区块链状态中。
 * @param transientSlot 瞬态存储中动态字节数组的槽位
 * @param memoryPointer 指向要写入解码后数组的内存位置的指针
 * @return endPointer 指向解码后数组末尾的指针
 */
  function readToPointer(
    TransientBytesArray transientSlot,//瞬态存储中动态字节数组的槽位
    uint256 memoryPointer//指向要写入解码后数组的内存位置的指针
  ) internal view returns (uint256 endPointer) {
    assembly {
      // 函数 extractByteArrayLength 用于从瞬态存储槽中提取动态字节数组的长度。
      function extractByteArrayLength(data) -> length {
        //在 Solidity 中，动态字节数组的长度编码方式是：
        // 长度 2（对于长数组）或 长度 2 + 1（对于短数组）。
        //短数组的长度编码：
        //实际长度乘以2（左移1位）
        //存储在最后一个字节中
        length := div(data, 2)//将数据除以2，得到数组的长度 
        // 1. 短数组（31 字节或更少）：
        // 数据直接存储在槽中
        // 最后一个字节用于存储长度
        // 长度编码为：length * 2
        // 最低位为 0
        // 2. 长数组（32 字节或更多）：
        // 槽中存储的是长度信息
        // 实际数据存储在其他位置（由槽的 keccak256 哈希确定的位置）
        // 长度编码为：length * 2 + 1
        // 最低位为 1
        //通过与 1 进行按位与操作，检查 data 的最低位是否为 1。
        //如果为 1，表示这是一个长数组（超过 31 字节）；如果为 0，表示这是一个短数组。
        let outOfPlaceEncoding := and(data, 1)
        if iszero(outOfPlaceEncoding) {//如果数据没有超出32字节
        //如果 outOfPlaceEncoding 为 0（即短数组）：
        //将 length 与 0x7f (127) 进行按位与操作。
        //这是因为短数组的长度存储在最后一个字节中，最大可以存储 31 字节的数据。
        //当我们将一个数与 0x7f 进行按位与操作时，会发生以下情况：
          //1. 最高位（第8位）总是变成0
          //2. 其他7位保持不变
          length := and(length, 0x7f)//将长度与0x7f进行按位与操作，得到数组的长度
        }
        //如果 eq(outOfPlaceEncoding, lt(length, 32)) 为真，
        //表示数组长度小于32字节，但使用了长数组编码
        //这个检查的目的是捕获以下矛盾情况：
        //数组长度小于 32 字节（应该使用短数组编码）
        //但实际上使用了长数组编码
        //lt(length, 32) 为 1
        //eq(1, 1) 为 1(true)
        //或者lt(length, 32) 为 0
        //eq(0, 0) 为 1(true)
        if eq(outOfPlaceEncoding, lt(length, 32)) {
          //存储 Panic 错误签名
          //在 Solidity 中，每个错误类型都有一个唯一的 4 字节标识符，
          //称为选择器。这个选择器是根据错误的签名计算出来的。
          //Panic 错误的签名是 Panic(uint256)，其选择器是这个签名的 
          //keccak256 哈希的前 4 字节。
          //Panic_ErrorSelector 的实际值应该是 0x4e487b71。
          //这是 keccak256("Panic(uint256)") 的前 4 字节。
          // Store the Panic error signature.
          mstore(0, Panic_ErrorSelector)
          //存储 Panic 错误代码
          //在代码中，这个错误代码被存储在 Panic_ErrorCodePointer 指向的内存位置。
          //这意味着它会成为 Panic 错误信息的一部分，用于提供更具体的错误原因。
          // Store the arithmetic (0x11) panic code.
          mstore(Panic_ErrorCodePointer, Panic_InvalidStorageByteArray)
          //这里Error_SelectorPointer 指向错误数据的起始位置，
          //而 Panic_ErrorLength 指定了要读取的字节数。
          //Panic_ErrorLength 的值是 36。这个值是由 Panic 错误的结构决定的。
          // Panic 错误消息通常由以下部分组成：
          // 字节的错误选择器（Panic_ErrorSelector）
          // 32 字节的错误代码（如 Panic_InvalidStorageByteArray）
          // 因此，总长度为 4 + 32 = 36 字节
          // revert(abi.encodeWithSignature("Panic(uint256)", 0x22))
          revert(Error_SelectorPointer, Panic_ErrorLength)
        }
      }
      //tload 是 "transient load" 的缩写，用于从瞬态存储中加载数据。
      let slotValue := tload(transientSlot)//瞬态存储槽的值
      let length := extractByteArrayLength(slotValue)//提取数组长度
      mstore(memoryPointer, length)//将数组长度存储在内存中
      //add(memoryPointer, 0x20) 将内存指针向前移动 32 字节。
      //这样做的目的是将指针从指向数组长度的位置移动到数组实际数据开始的位置。
      memoryPointer := add(memoryPointer, 0x20)//将内存指针移动到数组数据的开头
      switch and(slotValue, 1)//检查数组是否为短数组
      case 0 {
        // short byte array
        //not(0xff) 创建一个掩码，其中除了最后 8 位（1 字节）外，所有位都是 1。
        //0xff 是 11111111 (二进制)
        //not(0xff) 是 11111111 11111111 ... 11111111 00000000
        //(256 位，最后 8 位为 0)
        //and(slotValue, not(0xff)) 执行按位与操作：
        // 这会保留 slotValue 中除最后一个字节外的所有数据
        // 最后一个字节（用于存储长度信息）被设置为 0
        // 结果存储在 value 中，现在包含了原始短字节数组的数据，但不包括长度信息。
        // 这个操作之所以有效，是因为在 Solidity 中，短字节数组（长度小于 32 字节）的存储方式如下：
        // 数据存储在槽的高位字节中
        // 长度信息存储在槽的最后一个字节中
        // 通过移除最后一个字节，我们就得到了纯粹的数组数据，可以将其存储到内存中。
        let value := and(slotValue, not(0xff))
        //将 value 存储到内存中
        mstore(memoryPointer, value)
        //将 memoryPointer 加上 0x20，得到数组数据部分的结束指针。
        //这确保了下一次内存分配不会覆盖我们刚刚写入的数据。
        endPointer := add(memoryPointer, 0x20)
      }
      case 1 {
        // long byte array
        //这行代码的目的是为了准备计算长数组数据存储位置的哈希值。
        //在 Solidity 中，长数组（32字节或更长）的数据存储方式如下：
        //数组长度存储在 transientSlot 指定的槽中。
        //实际数据存储在 keccak256(transientSlot) 开始的连续槽中。
        mstore(0, transientSlot)
        // Calculate the slot of the data portion of the array
        //计算数组数据部分的槽位
        //keccak256(0, 0x20) 是一个哈希函数调用：
        //0 是内存中开始读取数据的位置。这里对应于之前 mstore(0, transientSlot) 存储数据的位置。
        //0x20 是要读取的字节数，等于 32 字节（一个完整的存储槽）。
        //这个哈希操作实际上是在计算 keccak256(transientSlot)，
        //因为 transientSlot 的值已经在之前被存储在内存位置 0。
        let dataTSlot := keccak256(0, 0x20)
        let i := 0
        for {

        } lt(i, length) {
          i := add(i, 0x20)
        } {
          //这行代码从瞬态存储的 dataTSlot 位置加载 32 字节的数据。
          //然后将这 32 字节的数据存储到内存中，位置是 memoryPointer + i。
          mstore(add(memoryPointer, i), tload(dataTSlot))
          //将 dataTSlot 增加 1，指向下一个瞬态存储槽。
          //为什么是加1：
          //在以太坊的瞬态存储模型中，连续的存储槽是通过简单地递增槽号来访问的。
          //每个槽可以存储32字节的数据，所以每次我们需要读取下一个32字节块时，只需将槽号加1即可。
          dataTSlot := add(dataTSlot, 1)
        }
        //将 memoryPointer 加上 i，得到数组数据部分的结束指针。
        //这确保了下一次内存分配不会覆盖我们刚刚写入的数据。
        endPointer := add(memoryPointer, i)
      }
    }
  }
//读取瞬态存储中的动态字节数组
  function read(TransientBytesArray transientSlot) internal view returns (bytes memory data) {
    uint256 dataPointer;//自由内存指针
    assembly {
      dataPointer := mload(0x40)//获取自由内存指针
      data := dataPointer//将 data 设置为这个指针
      //为什么存储 0：
      // 在 Solidity 中，动态数组（包括 bytes）的内存表示以 32 字节的长度字段开始。
      // 存储 0 实际上是在初始化这个长度字段，表示一个空的字节数组。
      // 初始化的重要性：
      // 这确保了 data 开始时是一个有效的空字节数组。
      // 防止了可能的未初始化内存读取，这在某些情况下可能导致安全问题。
      // 后续操作：
      // 在这之后，readToPointer 函数会被调用来填充实际的数据。
      mstore(data, 0)//在 data 指向的位置存储 0
    }
    uint256 endPointer = readToPointer(transientSlot, dataPointer);
    assembly {
      //将 endPointer 存储在自由内存指针的位置
      mstore(0x40, endPointer)
    }
  }

  /**
   * @dev Write a dynamic bytes array to transient storage.
   * @param transientSlot Slot for the dynamic bytes array in transient storage
   * @param memoryPointer Pointer to the memory location of the array to write
   */
  function write(TransientBytesArray transientSlot, bytes memory memoryPointer) internal {
    assembly {
      let length := mload(memoryPointer)
      memoryPointer := add(memoryPointer, 0x20)
      switch lt(length, 32)
      case 0 {
        // For long byte arrays, the length slot holds (length * 2 + 1)
        tstore(transientSlot, add(1, mul(2, length)))
        // Calculate the slot of the data portion of the array
        mstore(0, transientSlot)
        let dataTSlot := keccak256(0, 0x20)
        let i := 0
        for {

        } lt(i, length) {
          i := add(i, 0x20)
        } {
          tstore(dataTSlot, mload(add(memoryPointer, i)))
          dataTSlot := add(dataTSlot, 1)
        }
      }
      case 1 {
        // For short byte arrays, the first 31 bytes are the data and the last byte is (length * 2).
        let lengthByte := mul(2, length)
        let data := mload(memoryPointer)
        tstore(transientSlot, or(data, lengthByte))
      }
    }
  }

  function setEmpty(TransientBytesArray transientSlot) internal {
    assembly {
      tstore(transientSlot, 0)
    }
  }
}
