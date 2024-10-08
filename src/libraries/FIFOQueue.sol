// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.20;

// FIFOQueue 是一个先进先出（FIFO）队列，用于存储和管理一批数据。
// 它包含两个主要的索引：startIndex 和 nextIndex。
// startIndex 表示队列的起始位置，nextIndex 表示下一个要插入数据的位置。
// 通过这两个索引，可以有效地管理和访问队列中的数据。
struct FIFOQueue {
  uint128 startIndex;  // 队列的起始位置
  uint128 nextIndex;  // 下一个要插入数据的位置
  mapping(uint256 => uint32) data;  // 存储数据的映射
}

// @todo - make array tightly packed for gas efficiency with multiple reads/writes
//         also make a memory version of the array with (nextIndex, startIndex, storageSlot)
//         so that multiple storage reads aren't required for tx's using multiple functions

using FIFOQueueLib for FIFOQueue global;

library FIFOQueueLib {
  error FIFOQueueOutOfBounds();

  function empty(FIFOQueue storage arr) internal view returns (bool) {
    return arr.nextIndex == arr.startIndex;
  }

  function first(FIFOQueue storage arr) internal view returns (uint32) {
    if (arr.startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return arr.data[arr.startIndex];
  }

  function at(FIFOQueue storage arr, uint256 index) internal view returns (uint32) {
    index += arr.startIndex;
    if (index >= arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    return arr.data[index];
  }

  function length(FIFOQueue storage arr) internal view returns (uint128) {
    return arr.nextIndex - arr.startIndex;
  }

  function values(FIFOQueue storage arr) internal view returns (uint32[] memory _values) {
    uint256 startIndex = arr.startIndex;
    uint256 nextIndex = arr.nextIndex;
    uint256 len = nextIndex - startIndex;
    _values = new uint32[](len);

    for (uint256 i = 0; i < len; i++) {
      _values[i] = arr.data[startIndex + i];
    }

    return _values;
  }

  function push(FIFOQueue storage arr, uint32 value) internal {
    uint128 nextIndex = arr.nextIndex;
    arr.data[nextIndex] = value;
    arr.nextIndex = nextIndex + 1;
  }

  function shift(FIFOQueue storage arr) internal {
    uint128 startIndex = arr.startIndex;
    if (startIndex == arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    delete arr.data[startIndex];
    arr.startIndex = startIndex + 1;
  }

  function shiftN(FIFOQueue storage arr, uint128 n) internal {
    uint128 startIndex = arr.startIndex;
    if (startIndex + n > arr.nextIndex) {
      revert FIFOQueueOutOfBounds();
    }
    for (uint256 i = 0; i < n; i++) {
      delete arr.data[startIndex + i];
    }
    arr.startIndex = startIndex + n;
  }
}
