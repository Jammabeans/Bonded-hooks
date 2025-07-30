// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemoryCard.sol";
import "forge-std/console.sol";

contract MemoryCardTest is Test {
    MemoryCard card;

    // Test data constants
    bytes constant DATA1 = hex"11223344556677889900aabbccddeeff0011223344556677889900aabbccddeeff11223344556677889900aabbccddeeff0011223344556677889900aabbccddeeff";
    bytes constant DATA2 = hex"deadbeef";
    bytes constant DATA3 = hex"cafebabecafebabecafebabecafebabe";
    bytes constant DATA4 = hex"00";
    bytes constant DATA5 = hex"";

    // Much longer test data
    bytes constant DATA6 = hex"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    bytes constant DATA7 = hex"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    bytes constant DATA8 = hex"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    bytes constant DATA9 = hex"b0b1b2b3b4b5b6b7b8b9babbbcbdbebf" // 16 bytes
        hex"c0c1c2c3c4c5c6c7c8c9cacbcccdcecf" // 16 bytes
        hex"d0d1d2d3d4d5d6d7d8d9dadbdcdddedf" // 16 bytes
        hex"e0e1e2e3e4e5e6e7e8e9eaebecedeeef" // 16 bytes
        hex"f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff" // 16 bytes
        hex"00112233445566778899aabbccddeeff" // 16 bytes
        hex"ffeeddccbbaa99887766554433221100" // 16 bytes
        hex"1234567890abcdef1234567890abcdef"; // 16 bytes (total 128 bytes)

    // 256 bytes (should revert for store2)
    bytes DATA10;

    function setUp() public {
        card = new MemoryCard();
        // Initialize DATA10 at runtime (since memory bytes can't be constant)
        DATA10 = new bytes(256);
        for (uint i = 0; i < 256; i++) {
            DATA10[i] = bytes1(uint8(i));
        }
    }

    function testWriteAndRead() public {
        _testWriteAndRead(keccak256("foo"), DATA1);
        _testWriteAndRead(keccak256("bar"), DATA2);
        _testWriteAndRead(keccak256("baz"), DATA3);
        _testWriteAndRead(keccak256("qux"), DATA4);
        _testWriteAndRead(keccak256("empty"), DATA5);
        _testWriteAndRead(keccak256("long1"), DATA6);
        _testWriteAndRead(keccak256("long2"), DATA7);
        _testWriteAndRead(keccak256("long3"), DATA8);
        _testWriteAndRead(keccak256("long4"), DATA9);
    }

    function _testWriteAndRead(bytes32 key, bytes memory value) internal {
        uint256 gasBefore = gasleft();
        card.write(key, value);
        uint256 gasAfterWrite = gasleft();
        uint256 gasUsedWrite = gasBefore - gasAfterWrite;

        gasBefore = gasleft();
        bytes memory result = card.read(address(this), key);
        uint256 gasAfterRead = gasleft();
        uint256 gasUsedRead = gasBefore - gasAfterRead;

        assertEq(result, value, "Memory store: read/write failed");
        emit log_named_uint("Expected value length", value.length);
        emit log_named_uint("Gas used for memory write", gasUsedWrite);
        emit log_named_uint("Gas used for memory read", gasUsedRead);
    }

    function testClear() public {
        bytes32 key = keccak256("foo");
        card.write(key, "bar");
        card.clear(key);
        bytes memory result = card.read(address(this), key);
        assertEq(result.length, 0, "Memory store: clear failed");
    }

    function testStore2WriteAndRead() public {
        _testStore2WriteAndRead(keccak256("foo2"), DATA1);
        _testStore2WriteAndRead(keccak256("bar2"), DATA2);
        _testStore2WriteAndRead(keccak256("baz2"), DATA3);
        _testStore2WriteAndRead(keccak256("qux2"), DATA4);
        _testStore2WriteAndRead(keccak256("empty2"), DATA5);
        _testStore2WriteAndRead(keccak256("long1"), DATA6);
        _testStore2WriteAndRead(keccak256("long2"), DATA7);
        _testStore2WriteAndRead(keccak256("long3"), DATA8);
        _testStore2WriteAndRead(keccak256("long4"), DATA9);
        // DATA10 is 256 bytes, should revert
        //vm.expectRevert("Value too long for this creation code");
        //card.store2write(keccak256( DATA10);
    }

    function _testStore2WriteAndRead(bytes32 key, bytes memory runtime) internal {
        uint256 gasBefore = gasleft();
        card.store2write( runtime);
        uint256 gasAfterWrite = gasleft();
        uint256 gasUsedWrite = gasBefore - gasAfterWrite;

        gasBefore = gasleft();
        bytes memory code = card.store2read(address(this));
        uint256 gasAfterRead = gasleft();
        uint256 gasUsedRead = gasBefore - gasAfterRead;

        emit log_named_uint("Returned code length", code.length);
        emit log_named_uint("Expected code length", runtime.length);
         //assertEq(code, runtime, "Store2: code mismatch");
         
         
        emit log_named_uint("Gas used for store2 write (contract deploy)", gasUsedWrite);
        emit log_named_uint("Gas used for store2 read (extcodecopy)", gasUsedRead);
    }

    function testStore2Clear() public {
        _testStore2Clear(keccak256("foo2"), DATA1);
        _testStore2Clear(keccak256("bar2"), DATA2);
        _testStore2Clear(keccak256("baz2"), DATA3);
        _testStore2Clear(keccak256("qux2"), DATA4);
        _testStore2Clear(keccak256("empty2"), DATA5);
        _testStore2Clear(keccak256("long1"), DATA6);
        _testStore2Clear(keccak256("long2"), DATA7);
        _testStore2Clear(keccak256("long3"), DATA8);
        _testStore2Clear(keccak256("long4"), DATA9);
        // DATA10 is 256 bytes, should revert on store2write
        ///vm.expectRevert("Value too long for this creation code");
        //card.store2write(keccak256("toolong2"), DATA10);
    }

    function _testStore2Clear(bytes32 key, bytes memory runtime) internal {
        card.store2write( runtime);
        card.store2clear();
        // After clear, should revert on read
        vm.expectRevert("No contract stored");
        card.store2read(address(this));
    }
}