// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/MemoryCard.sol";
import "forge-std/console.sol";

contract MemoryCardTest is Test {
    MemoryCard card;

    // Test data blobs — initialized in setUp to even intervals (0,32,64,...,224,255)
    // We use non-constant bytes and initialize them at runtime so lengths are exact and easy to adjust.
    bytes DATA1;
    bytes DATA2;
    bytes DATA3;
    bytes DATA4;
    bytes DATA5;
    bytes DATA6;
    bytes DATA7;
    bytes DATA8;
    bytes DATA9;
 
    // 256 bytes buffer kept for legacy tests (initialized as 256 bytes)
    bytes DATA10;

// Arrays to collect gas metrics for in-memory store tests
uint256[] memLens;
uint256[] memWriteGas;
uint256[] memReadGas;

// Arrays to collect gas metrics for ROM store tests
uint256[] romLens;
uint256[] romWriteGas;
uint256[] romReadGas;
    function setUp() public {
        card = new MemoryCard();
        // Initialize DATA10 at runtime (since memory bytes can't be constant)
        DATA10 = new bytes(256);
        for (uint i = 0; i < 256; i++) {
            DATA10[i] = bytes1(uint8(i));
        }
 
        // Initialize DATA1..DATA9 to even intervals from 0 up to 255 (inclusive).
        // Chosen lengths: 0, 32, 64, 96, 128, 160, 192, 224, 255
        uint16[9] memory lengths = [uint16(0), 32, 64, 96, 128, 160, 192, 224, 255];
        for (uint idx = 0; idx < 9; idx++) {
            uint256 len = lengths[idx];
            bytes memory b = new bytes(len);
            // fill with a simple repeating pattern (0..255) which is deterministic
            for (uint j = 0; j < len; j++) {
                b[j] = bytes1(uint8(j));
            }
            if (idx == 0) DATA1 = b;
            else if (idx == 1) DATA2 = b;
            else if (idx == 2) DATA3 = b;
            else if (idx == 3) DATA4 = b;
            else if (idx == 4) DATA5 = b;
            else if (idx == 5) DATA6 = b;
            else if (idx == 6) DATA7 = b;
            else if (idx == 7) DATA8 = b;
            else if (idx == 8) DATA9 = b;
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

    function testsaveToRomAndRead() public {
        _testsaveToRomAndRead(keccak256("foo2"), DATA1);
        _testsaveToRomAndRead(keccak256("bar2"), DATA2);
        _testsaveToRomAndRead(keccak256("baz2"), DATA3);
        _testsaveToRomAndRead(keccak256("qux2"), DATA4);
        _testsaveToRomAndRead(keccak256("empty2"), DATA5);
        _testsaveToRomAndRead(keccak256("long1"), DATA6);
        _testsaveToRomAndRead(keccak256("long2"), DATA7);
        _testsaveToRomAndRead(keccak256("long3"), DATA8);
        _testsaveToRomAndRead(keccak256("long4"), DATA9);
        // DATA10 is 256 bytes, should revert
        //vm.expectRevert("Value too long for this creation code");
        //card.saveToRom(keccak256( DATA10);
    }

    function _testsaveToRomAndRead(bytes32 key, bytes memory runtime) internal {
        uint256 gasBefore = gasleft();
        card.saveToRom( runtime);
        uint256 gasAfterWrite = gasleft();
        uint256 gasUsedWrite = gasBefore - gasAfterWrite;

        gasBefore = gasleft();
        bytes memory code = card.readFromRom(address(this));
        uint256 gasAfterRead = gasleft();
        uint256 gasUsedRead = gasBefore - gasAfterRead;

        emit log_named_uint("Returned code length", code.length);
        emit log_named_uint("Expected code length", runtime.length);
         //assertEq(code, runtime, "Store2: code mismatch");
         
         
        emit log_named_uint("Gas used for store2 write (contract deploy)", gasUsedWrite);
        emit log_named_uint("Gas used for store2 read (extcodecopy)", gasUsedRead);
    }
    // Helper: convert uint -> decimal string
    function uintToString(uint256 v) internal pure returns (string memory) {
        if (v == 0) {
            return "0";
        }
        uint256 j = v;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (v != 0) {
            k = k - 1;
            uint8 digit = uint8(48 + uint8(v % 10));
            bstr[k] = bytes1(digit);
            v /= 10;
        }
        return string(bstr);
    }

    // Helper: pad left with spaces to fixed width
    function padLeft(string memory s, uint256 width) internal pure returns (string memory) {
        bytes memory bs = bytes(s);
        if (bs.length >= width) {
            return s;
        }
        bytes memory out = new bytes(width);
        uint256 pad = width - bs.length;
        for (uint256 i = 0; i < pad; i++) {
            out[i] = bytes1(uint8(0x20)); // space
        }
        for (uint256 i = 0; i < bs.length; i++) {
            out[pad + i] = bs[i];
        }
        return string(out);
    }

    // Helper: format signed percentage scaled by 100 (two decimal places) e.g. 1234 -> "12.34%", -1234 -> "-12.34%"
    function formatSignedPercent(int256 scaledX100) internal pure returns (string memory) {
        if (scaledX100 == 0) {
            return "0.00%";
        }
        bool negative = scaledX100 < 0;
        uint256 absv = uint256(negative ? -scaledX100 : scaledX100);
        uint256 intPart = absv / 100;
        uint256 frac = absv % 100;
        // ensure two digits for frac
        string memory fracStr = uintToString(frac);
        if (frac < 10) {
            fracStr = string.concat("0", fracStr);
        }
        string memory s = string.concat(uintToString(intPart), ".", fracStr, "%");
        if (negative) {
            return string.concat("-", s);
        }
        return s;
    }

    // Helper: format a table row for logging with fixed column widths
    // wPct and rPct are percentage strings like "12.34%" or "-5.67%"
    function formatRow(
        uint256 idx,
        uint256 len,
        uint256 mW,
        uint256 rW,
        uint256 wDiff,
        string memory wPct,
        uint256 mR,
        uint256 rR,
        uint256 rDiff,
        string memory rPct
    ) internal pure returns (string memory) {
        // column widths chosen to accommodate observed values:
        // idx:2, len:3, memW:6, romW:6, wDiff:6, wPct:7, memR:5, romR:5, rDiff:5, rPct:7
        return string.concat(
            padLeft(uintToString(idx), 2), " | ",
            padLeft(uintToString(len), 3), " | ",
            padLeft(uintToString(mW), 6), " | ",
            padLeft(uintToString(rW), 6), " | ",
            padLeft(uintToString(wDiff), 6), " | ",
            padLeft(wPct, 7), " | ",
            padLeft(uintToString(mR), 5), " | ",
            padLeft(uintToString(rR), 5), " | ",
            padLeft(uintToString(rDiff), 5), " | ",
            padLeft(rPct, 7)
        );
    }

    // New combined gas-comparison test: runs memory and ROM store/read back-to-back
    // and prints a side-by-side comparison (absolute diff + basis points).
    function testGasComparison() public {
        uint256 gasBefore;
        uint256 memW;
        uint256 memR;
        uint256 romW;
        uint256 romR;
        bytes memory returned;

        // Dataset 1
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp1"), DATA1);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp1"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA1);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA1.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA1.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 2
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp2"), DATA2);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp2"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA2);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA2.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA2.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 3
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp3"), DATA3);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp3"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA3);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA3.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA3.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 4
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp4"), DATA4);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp4"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA4);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA4.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA4.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 5 (empty)
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp5"), DATA5);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp5"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA5);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA5.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA5.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 6 (long)
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp6"), DATA6);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp6"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA6);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA6.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA6.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 7
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp7"), DATA7);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp7"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA7);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA7.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA7.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 8
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp8"), DATA8);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp8"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA8);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA8.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA8.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Dataset 9
        gasBefore = gasleft();
        card.write(keccak256("foo_cmp9"), DATA9);
        memW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.read(address(this), keccak256("foo_cmp9"));
        memR = gasBefore - gasleft();

        gasBefore = gasleft();
        card.saveToRom(DATA9);
        romW = gasBefore - gasleft();
        gasBefore = gasleft();
        returned = card.readFromRom(address(this));
        romR = gasBefore - gasleft();

        memLens.push(DATA9.length);
        memWriteGas.push(memW);
        memReadGas.push(memR);
        romLens.push(DATA9.length);
        romWriteGas.push(romW);
        romReadGas.push(romR);

        // Print a compact header (one row per dataset)
        emit log("=== Gas comparison (per dataset) ===");

        // Build a fixed-width header so rows align in logs.
        string memory header = string.concat(
            padLeft("idx", 2), " | ",
            padLeft("len", 3), " | ",
            padLeft("memW", 6), " | ",
            padLeft("romW", 6), " | ",
            padLeft("wDiff", 6), " | ",
            padLeft("w%", 7), " | ",
            padLeft("memR", 5), " | ",
            padLeft("romR", 5), " | ",
            padLeft("rDiff", 5), " | ",
            padLeft("r%", 7)
        );
        emit log(header);

        // Separator line matching approximate width of header (visual aid)
        emit log("----+-----+--------+--------+--------+---------+-------+-------+-------+---------");

        for (uint256 i = 0; i < memLens.length; i++) {
            uint256 len = memLens[i];

            uint256 mW = memWriteGas[i];
            uint256 rW = romWriteGas[i];
            uint256 writeDiff = mW > rW ? mW - rW : rW - mW;
            // Signed percent scaled by 100 (two decimal places).
            // Positive => ROM more expensive than MEM; Negative => ROM cheaper than MEM (what you asked for).
            int256 writePctScaledSigned;
            if (mW == 0) {
                if (rW == 0) {
                    writePctScaledSigned = 0;
                } else {
                    // denom = rW to avoid division by zero; percent = (rW - mW) / rW
                    writePctScaledSigned = (int256(rW) - int256(mW)) * 10000 / int256(rW);
                }
            } else {
                // percent = (rW - mW) / mW
                writePctScaledSigned = (int256(rW) - int256(mW)) * 10000 / int256(mW);
            }

            uint256 mR = memReadGas[i];
            uint256 rR = romReadGas[i];
            uint256 readDiff = mR > rR ? mR - rR : rR - mR;
            int256 readPctScaledSigned;
            if (mR == 0) {
                if (rR == 0) {
                    readPctScaledSigned = 0;
                } else {
                    readPctScaledSigned = (int256(rR) - int256(mR)) * 10000 / int256(rR);
                }
            } else {
                readPctScaledSigned = (int256(rR) - int256(mR)) * 10000 / int256(mR);
            }

            string memory writePctStr = formatSignedPercent(writePctScaledSigned);
            string memory readPctStr = formatSignedPercent(readPctScaledSigned);

            string memory row = formatRow(
                i,
                len,
                mW,
                rW,
                writeDiff,
                writePctStr,
                mR,
                rR,
                readDiff,
                readPctStr
            );
            emit log(row);
        }
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
        // DATA10 is 256 bytes, should revert on saveToRom
        ///vm.expectRevert("Value too long for this creation code");
        //card.saveToRom(keccak256("toolong2"), DATA10);
    }

    function _testStore2Clear(bytes32 key, bytes memory runtime) internal {
        card.saveToRom( runtime);
        card.store2clear();
        // After clear, should revert on read
        vm.expectRevert("No contract stored");
        card.readFromRom(address(this));
    }
}