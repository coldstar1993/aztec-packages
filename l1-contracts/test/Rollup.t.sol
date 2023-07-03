// SPDX-License-Identifier: Apache-2.0
// Copyright 2023 Aztec Labs.
pragma solidity >=0.8.18;

import {Test} from "forge-std/Test.sol";

import {DecoderTest} from "./Decoder.t.sol";

import {DataStructures} from "@aztec/core/libraries/DataStructures.sol";

import {Registry} from "@aztec/core/messagebridge/Registry.sol";
import {Inbox} from "@aztec/core/messagebridge/Inbox.sol";
import {Outbox} from "@aztec/core/messagebridge/Outbox.sol";
import {Errors} from "@aztec/core/libraries/Errors.sol";
import {Rollup} from "@aztec/core/Rollup.sol";

/**
 * Blocks are generated using the `integration_l1_publisher.test.ts` tests.
 * Main use of these test is shorter cycles when updating the decoder contract.
 */
contract RollupTest is DecoderTest {
  function testEmptyBlock() public override(DecoderTest) {
    (,, bytes32 endStateHash,, bytes32[] memory l2ToL1Msgs, bytes32[] memory l1ToL2Msgs) =
      helper.decode(block_empty_1);

    vm.record();
    rollup.process(bytes(""), block_empty_1);

    (, bytes32[] memory inboxWrites) = vm.accesses(address(inbox));
    (, bytes32[] memory outboxWrites) = vm.accesses(address(outbox));

    assertEq(inboxWrites.length, 0, "Invalid inbox writes");
    assertEq(outboxWrites.length, 0, "Invalid outbox writes");

    for (uint256 i = 0; i < l2ToL1Msgs.length; i++) {
      assertEq(l2ToL1Msgs[i], bytes32(0), "Invalid l2ToL1Msgs");
      assertFalse(outbox.contains(l2ToL1Msgs[i]), "msg in outbox");
    }
    for (uint256 i = 0; i < l1ToL2Msgs.length; i++) {
      assertEq(l1ToL2Msgs[i], bytes32(0), "Invalid l1ToL2Msgs");
      assertFalse(inbox.contains(l1ToL2Msgs[i]), "msg in inbox");
    }

    assertEq(rollup.rollupStateHash(), endStateHash, "Invalid rollup state hash");
  }

  function testRevertInvalidChainId() public {
    bytes memory block_ = block_empty_1;
    assembly {
      mstore(add(block_, 0x20), 0x420)
    }

    vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__InvalidChainId.selector, 0x420, 31337));
    rollup.process(bytes(""), block_);
  }

  function testRevertInvalidVersion() public {
    bytes memory block_ = block_empty_1;
    assembly {
      mstore(add(block_, 0x40), 0x420)
    }

    vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__InvalidVersion.selector, 0x420, 1));
    rollup.process(bytes(""), block_);
  }

  function testRevertTimestampInFuture() public {
    bytes memory block_ = block_empty_1;

    uint256 ts = block.timestamp + 1;
    assembly {
      mstore(add(block_, 0x80), ts)
    }

    vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__TimestampInFuture.selector));
    rollup.process(bytes(""), block_);
  }

  function testRevertTimestampTooOld() public {
    bytes memory block_ = block_empty_1;

    // Overwrite in the rollup contract
    vm.store(address(rollup), bytes32(uint256(1)), bytes32(uint256(block.timestamp)));

    vm.expectRevert(abi.encodeWithSelector(Errors.Rollup__TimestampTooOld.selector));
    rollup.process(bytes(""), block_);
  }

  function testMixBlock() public override(DecoderTest) {
    (,, bytes32 endStateHash,, bytes32[] memory l2ToL1Msgs, bytes32[] memory l1ToL2Msgs) =
      helper.decode(block_mixed_1);

    bytes32[] memory expectedL1ToL2Msgs = _populateInbox();

    for (uint256 i = 0; i < l1ToL2Msgs.length; i++) {
      assertTrue(inbox.contains(l1ToL2Msgs[i]), "msg not in inbox");
    }

    vm.record();
    rollup.process(bytes(""), block_mixed_1);

    (, bytes32[] memory inboxWrites) = vm.accesses(address(inbox));
    (, bytes32[] memory outboxWrites) = vm.accesses(address(outbox));

    assertEq(inboxWrites.length, 16, "Invalid inbox writes");
    assertEq(outboxWrites.length, 8, "Invalid outbox writes");

    for (uint256 i = 0; i < l2ToL1Msgs.length; i++) {
      // recreate the value generated by `integration_l1_publisher.test.ts`.
      bytes32 expectedValue = bytes32(uint256(0x300 + 32 * (1 + i / 2) + i % 2));
      assertEq(l2ToL1Msgs[i], expectedValue, "Invalid l2ToL1Msgs");
      assertTrue(outbox.contains(l2ToL1Msgs[i]), "msg not in outbox");
    }

    for (uint256 i = 0; i < l1ToL2Msgs.length; i++) {
      assertEq(l1ToL2Msgs[i], expectedL1ToL2Msgs[i], "Invalid l1ToL2Msgs");
      assertFalse(inbox.contains(l1ToL2Msgs[i]), "msg not consumed");
    }

    assertEq(rollup.rollupStateHash(), endStateHash, "Invalid rollup state hash");
  }
}
