// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { MemoryPointer, OffsetOrLengthMask, _OneWord } from './MemoryPointer.sol';

type CalldataPointer is uint256;

using CalldataPointerLib for CalldataPointer global;
using CalldataReaders for CalldataPointer global;

CalldataPointer constant CalldataStart = CalldataPointer.wrap(0x04);

library CalldataPointerLib {
  function isNull(CalldataPointer a) internal pure returns (bool b) {
    assembly {
      b := iszero(a)
    }
  }

  function lt(CalldataPointer a, CalldataPointer b) internal pure returns (bool c) {
    assembly {
      c := lt(a, b)
    }
  }

  function gt(CalldataPointer a, CalldataPointer b) internal pure returns (bool c) {
    assembly {
      c := gt(a, b)
    }
  }

  function eq(CalldataPointer a, CalldataPointer b) internal pure returns (bool c) {
    assembly {
      c := eq(a, b)
    }
  }

  /// @dev Resolves an offset stored at `cdPtr + headOffset` to a calldata pointer.
  ///      `cdPtr` must point to some parent object with a dynamic type's head
  ///      stored at `cdPtr + headOffset`.
  function pptr(
    CalldataPointer cdPtr,
    uint256 headOffset
  ) internal pure returns (CalldataPointer cdPtrChild) {
    cdPtrChild = cdPtr.offset(cdPtr.offset(headOffset).readMaskedUint32());
  }

  /// @dev Resolves an offset stored at `cdPtr` to a calldata pointer.
  ///      `cdPtr` must point to some parent object with a dynamic type as its
  ///      first member, e.g. `struct { bytes data; }`
  function pptr(CalldataPointer cdPtr) internal pure returns (CalldataPointer cdPtrChild) {
    cdPtrChild = cdPtr.offset(cdPtr.readMaskedUint32());
  }

  /// @dev Returns the calldata pointer one word after `cdPtr`.
  function next(CalldataPointer cdPtr) internal pure returns (CalldataPointer cdPtrNext) {
    assembly {
      cdPtrNext := add(cdPtr, _OneWord)
    }
  }

  /// @dev Returns the calldata pointer `_offset` bytes after `cdPtr`.
  function offset(
    CalldataPointer cdPtr,
    uint256 _offset
  ) internal pure returns (CalldataPointer cdPtrNext) {
    assembly {
      cdPtrNext := add(cdPtr, _offset)
    }
  }

  /// @dev Copies `size` bytes from calldata starting at `src` to memory at
  ///      `dst`.
  function copy(CalldataPointer src, MemoryPointer dst, uint256 size) internal pure {
    assembly {
      calldatacopy(dst, src, size)
    }
  }
}

library CalldataReaders {
  /// @dev Reads the value at `cdPtr` and applies a mask to return only the
  ///      last 4 bytes.
  function readMaskedUint32(CalldataPointer cdPtr) internal pure returns (uint256 value) {
    value = cdPtr.readUint256() & OffsetOrLengthMask;
  }

  /// @dev Reads the bool at `cdPtr` in calldata.
  function readBool(CalldataPointer cdPtr) internal pure returns (bool value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the address at `cdPtr` in calldata.
  function readAddress(CalldataPointer cdPtr) internal pure returns (address value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes1 at `cdPtr` in calldata.
  function readBytes1(CalldataPointer cdPtr) internal pure returns (bytes1 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes2 at `cdPtr` in calldata.
  function readBytes2(CalldataPointer cdPtr) internal pure returns (bytes2 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes3 at `cdPtr` in calldata.
  function readBytes3(CalldataPointer cdPtr) internal pure returns (bytes3 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes4 at `cdPtr` in calldata.
  function readBytes4(CalldataPointer cdPtr) internal pure returns (bytes4 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes5 at `cdPtr` in calldata.
  function readBytes5(CalldataPointer cdPtr) internal pure returns (bytes5 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes6 at `cdPtr` in calldata.
  function readBytes6(CalldataPointer cdPtr) internal pure returns (bytes6 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes7 at `cdPtr` in calldata.
  function readBytes7(CalldataPointer cdPtr) internal pure returns (bytes7 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes8 at `cdPtr` in calldata.
  function readBytes8(CalldataPointer cdPtr) internal pure returns (bytes8 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes9 at `cdPtr` in calldata.
  function readBytes9(CalldataPointer cdPtr) internal pure returns (bytes9 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes10 at `cdPtr` in calldata.
  function readBytes10(CalldataPointer cdPtr) internal pure returns (bytes10 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes11 at `cdPtr` in calldata.
  function readBytes11(CalldataPointer cdPtr) internal pure returns (bytes11 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes12 at `cdPtr` in calldata.
  function readBytes12(CalldataPointer cdPtr) internal pure returns (bytes12 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes13 at `cdPtr` in calldata.
  function readBytes13(CalldataPointer cdPtr) internal pure returns (bytes13 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes14 at `cdPtr` in calldata.
  function readBytes14(CalldataPointer cdPtr) internal pure returns (bytes14 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes15 at `cdPtr` in calldata.
  function readBytes15(CalldataPointer cdPtr) internal pure returns (bytes15 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes16 at `cdPtr` in calldata.
  function readBytes16(CalldataPointer cdPtr) internal pure returns (bytes16 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes17 at `cdPtr` in calldata.
  function readBytes17(CalldataPointer cdPtr) internal pure returns (bytes17 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes18 at `cdPtr` in calldata.
  function readBytes18(CalldataPointer cdPtr) internal pure returns (bytes18 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes19 at `cdPtr` in calldata.
  function readBytes19(CalldataPointer cdPtr) internal pure returns (bytes19 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes20 at `cdPtr` in calldata.
  function readBytes20(CalldataPointer cdPtr) internal pure returns (bytes20 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes21 at `cdPtr` in calldata.
  function readBytes21(CalldataPointer cdPtr) internal pure returns (bytes21 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes22 at `cdPtr` in calldata.
  function readBytes22(CalldataPointer cdPtr) internal pure returns (bytes22 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes23 at `cdPtr` in calldata.
  function readBytes23(CalldataPointer cdPtr) internal pure returns (bytes23 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes24 at `cdPtr` in calldata.
  function readBytes24(CalldataPointer cdPtr) internal pure returns (bytes24 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes25 at `cdPtr` in calldata.
  function readBytes25(CalldataPointer cdPtr) internal pure returns (bytes25 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes26 at `cdPtr` in calldata.
  function readBytes26(CalldataPointer cdPtr) internal pure returns (bytes26 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes27 at `cdPtr` in calldata.
  function readBytes27(CalldataPointer cdPtr) internal pure returns (bytes27 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes28 at `cdPtr` in calldata.
  function readBytes28(CalldataPointer cdPtr) internal pure returns (bytes28 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes29 at `cdPtr` in calldata.
  function readBytes29(CalldataPointer cdPtr) internal pure returns (bytes29 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes30 at `cdPtr` in calldata.
  function readBytes30(CalldataPointer cdPtr) internal pure returns (bytes30 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes31 at `cdPtr` in calldata.
  function readBytes31(CalldataPointer cdPtr) internal pure returns (bytes31 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the bytes32 at `cdPtr` in calldata.
  function readBytes32(CalldataPointer cdPtr) internal pure returns (bytes32 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint8 at `cdPtr` in calldata.
  function readUint8(CalldataPointer cdPtr) internal pure returns (uint8 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint16 at `cdPtr` in calldata.
  function readUint16(CalldataPointer cdPtr) internal pure returns (uint16 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint24 at `cdPtr` in calldata.
  function readUint24(CalldataPointer cdPtr) internal pure returns (uint24 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint32 at `cdPtr` in calldata.
  function readUint32(CalldataPointer cdPtr) internal pure returns (uint32 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint40 at `cdPtr` in calldata.
  function readUint40(CalldataPointer cdPtr) internal pure returns (uint40 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint48 at `cdPtr` in calldata.
  function readUint48(CalldataPointer cdPtr) internal pure returns (uint48 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint56 at `cdPtr` in calldata.
  function readUint56(CalldataPointer cdPtr) internal pure returns (uint56 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint64 at `cdPtr` in calldata.
  function readUint64(CalldataPointer cdPtr) internal pure returns (uint64 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint72 at `cdPtr` in calldata.
  function readUint72(CalldataPointer cdPtr) internal pure returns (uint72 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint80 at `cdPtr` in calldata.
  function readUint80(CalldataPointer cdPtr) internal pure returns (uint80 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint88 at `cdPtr` in calldata.
  function readUint88(CalldataPointer cdPtr) internal pure returns (uint88 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint96 at `cdPtr` in calldata.
  function readUint96(CalldataPointer cdPtr) internal pure returns (uint96 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint104 at `cdPtr` in calldata.
  function readUint104(CalldataPointer cdPtr) internal pure returns (uint104 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint112 at `cdPtr` in calldata.
  function readUint112(CalldataPointer cdPtr) internal pure returns (uint112 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint120 at `cdPtr` in calldata.
  function readUint120(CalldataPointer cdPtr) internal pure returns (uint120 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint128 at `cdPtr` in calldata.
  function readUint128(CalldataPointer cdPtr) internal pure returns (uint128 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint136 at `cdPtr` in calldata.
  function readUint136(CalldataPointer cdPtr) internal pure returns (uint136 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint144 at `cdPtr` in calldata.
  function readUint144(CalldataPointer cdPtr) internal pure returns (uint144 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint152 at `cdPtr` in calldata.
  function readUint152(CalldataPointer cdPtr) internal pure returns (uint152 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint160 at `cdPtr` in calldata.
  function readUint160(CalldataPointer cdPtr) internal pure returns (uint160 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint168 at `cdPtr` in calldata.
  function readUint168(CalldataPointer cdPtr) internal pure returns (uint168 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint176 at `cdPtr` in calldata.
  function readUint176(CalldataPointer cdPtr) internal pure returns (uint176 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint184 at `cdPtr` in calldata.
  function readUint184(CalldataPointer cdPtr) internal pure returns (uint184 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint192 at `cdPtr` in calldata.
  function readUint192(CalldataPointer cdPtr) internal pure returns (uint192 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint200 at `cdPtr` in calldata.
  function readUint200(CalldataPointer cdPtr) internal pure returns (uint200 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint208 at `cdPtr` in calldata.
  function readUint208(CalldataPointer cdPtr) internal pure returns (uint208 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint216 at `cdPtr` in calldata.
  function readUint216(CalldataPointer cdPtr) internal pure returns (uint216 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint224 at `cdPtr` in calldata.
  function readUint224(CalldataPointer cdPtr) internal pure returns (uint224 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint232 at `cdPtr` in calldata.
  function readUint232(CalldataPointer cdPtr) internal pure returns (uint232 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint240 at `cdPtr` in calldata.
  function readUint240(CalldataPointer cdPtr) internal pure returns (uint240 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint248 at `cdPtr` in calldata.
  function readUint248(CalldataPointer cdPtr) internal pure returns (uint248 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the uint256 at `cdPtr` in calldata.
  function readUint256(CalldataPointer cdPtr) internal pure returns (uint256 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int8 at `cdPtr` in calldata.
  function readInt8(CalldataPointer cdPtr) internal pure returns (int8 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int16 at `cdPtr` in calldata.
  function readInt16(CalldataPointer cdPtr) internal pure returns (int16 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int24 at `cdPtr` in calldata.
  function readInt24(CalldataPointer cdPtr) internal pure returns (int24 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int32 at `cdPtr` in calldata.
  function readInt32(CalldataPointer cdPtr) internal pure returns (int32 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int40 at `cdPtr` in calldata.
  function readInt40(CalldataPointer cdPtr) internal pure returns (int40 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int48 at `cdPtr` in calldata.
  function readInt48(CalldataPointer cdPtr) internal pure returns (int48 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int56 at `cdPtr` in calldata.
  function readInt56(CalldataPointer cdPtr) internal pure returns (int56 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int64 at `cdPtr` in calldata.
  function readInt64(CalldataPointer cdPtr) internal pure returns (int64 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int72 at `cdPtr` in calldata.
  function readInt72(CalldataPointer cdPtr) internal pure returns (int72 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int80 at `cdPtr` in calldata.
  function readInt80(CalldataPointer cdPtr) internal pure returns (int80 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int88 at `cdPtr` in calldata.
  function readInt88(CalldataPointer cdPtr) internal pure returns (int88 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int96 at `cdPtr` in calldata.
  function readInt96(CalldataPointer cdPtr) internal pure returns (int96 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int104 at `cdPtr` in calldata.
  function readInt104(CalldataPointer cdPtr) internal pure returns (int104 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int112 at `cdPtr` in calldata.
  function readInt112(CalldataPointer cdPtr) internal pure returns (int112 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int120 at `cdPtr` in calldata.
  function readInt120(CalldataPointer cdPtr) internal pure returns (int120 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int128 at `cdPtr` in calldata.
  function readInt128(CalldataPointer cdPtr) internal pure returns (int128 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int136 at `cdPtr` in calldata.
  function readInt136(CalldataPointer cdPtr) internal pure returns (int136 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int144 at `cdPtr` in calldata.
  function readInt144(CalldataPointer cdPtr) internal pure returns (int144 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int152 at `cdPtr` in calldata.
  function readInt152(CalldataPointer cdPtr) internal pure returns (int152 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int160 at `cdPtr` in calldata.
  function readInt160(CalldataPointer cdPtr) internal pure returns (int160 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int168 at `cdPtr` in calldata.
  function readInt168(CalldataPointer cdPtr) internal pure returns (int168 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int176 at `cdPtr` in calldata.
  function readInt176(CalldataPointer cdPtr) internal pure returns (int176 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int184 at `cdPtr` in calldata.
  function readInt184(CalldataPointer cdPtr) internal pure returns (int184 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int192 at `cdPtr` in calldata.
  function readInt192(CalldataPointer cdPtr) internal pure returns (int192 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int200 at `cdPtr` in calldata.
  function readInt200(CalldataPointer cdPtr) internal pure returns (int200 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int208 at `cdPtr` in calldata.
  function readInt208(CalldataPointer cdPtr) internal pure returns (int208 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int216 at `cdPtr` in calldata.
  function readInt216(CalldataPointer cdPtr) internal pure returns (int216 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int224 at `cdPtr` in calldata.
  function readInt224(CalldataPointer cdPtr) internal pure returns (int224 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int232 at `cdPtr` in calldata.
  function readInt232(CalldataPointer cdPtr) internal pure returns (int232 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int240 at `cdPtr` in calldata.
  function readInt240(CalldataPointer cdPtr) internal pure returns (int240 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int248 at `cdPtr` in calldata.
  function readInt248(CalldataPointer cdPtr) internal pure returns (int248 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }

  /// @dev Reads the int256 at `cdPtr` in calldata.
  function readInt256(CalldataPointer cdPtr) internal pure returns (int256 value) {
    assembly {
      value := calldataload(cdPtr)
    }
  }
}
