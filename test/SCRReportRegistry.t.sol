// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SCRReportRegistry} from "../src/SCRReportRegistry.sol";

contract SCRReportRegistryTest is Test {
    SCRReportRegistry reg;
    address admin = makeAddr("admin");
    address attester = makeAddr("attester");
    address rando = makeAddr("rando");
    bytes32 constant H1 = keccak256("report one");
    bytes32 constant H2 = keccak256("report two");
    bytes32 constant V = bytes32("1.8.2");
    bytes32 constant LOC = bytes32("British Columbia");
    bytes32 constant PROF = bytes32("neocloud");

    event ReportAttested(bytes32 indexed sha256Hash, uint32 indexed number, bytes32 modelVersion, bytes32 location, bytes32 profile);
    event ReportRevoked(bytes32 indexed sha256Hash, bool revoked);

    function setUp() public { reg = new SCRReportRegistry(admin, attester); }

    function test_constructor() public view {
        assertTrue(reg.hasRole(reg.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(reg.hasRole(reg.ATTESTER_ROLE(), attester));
        assertEq(reg.count(), 0);
    }

    function test_constructor_zero() public {
        vm.expectRevert(SCRReportRegistry.ZeroAddress.selector);
        new SCRReportRegistry(address(0), attester);
        vm.expectRevert(SCRReportRegistry.ZeroAddress.selector);
        new SCRReportRegistry(admin, address(0));
    }

    function test_attest_and_verify() public {
        vm.warp(1_800_000_000);
        vm.expectEmit(address(reg));
        emit ReportAttested(H1, 1, V, LOC, PROF);
        vm.prank(attester);
        uint32 n = reg.attest(H1, V, LOC, PROF);
        assertEq(n, 1);
        (uint64 issued, bool revoked, uint32 number, bytes32 mv, bytes32 loc, bytes32 prof) = reg.verify(H1);
        assertEq(issued, 1_800_000_000); assertFalse(revoked); assertEq(number, 1);
        assertEq(mv, V); assertEq(loc, LOC); assertEq(prof, PROF);
        vm.prank(attester);
        assertEq(reg.attest(H2, V, LOC, PROF), 2);
        assertEq(reg.count(), 2);
    }

    function test_verify_unknown() public view {
        (uint64 issued,, uint32 number,,,) = reg.verify(H1);
        assertEq(issued, 0); assertEq(number, 0);
    }

    function test_attest_reverts() public {
        vm.startPrank(attester);
        vm.expectRevert(SCRReportRegistry.ZeroHash.selector);
        reg.attest(bytes32(0), V, LOC, PROF);
        reg.attest(H1, V, LOC, PROF);
        vm.expectRevert(SCRReportRegistry.AlreadyAttested.selector);
        reg.attest(H1, V, LOC, PROF);
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, rando, reg.ATTESTER_ROLE()));
        vm.prank(rando);
        reg.attest(H2, V, LOC, PROF);
    }

    function test_revoke() public {
        vm.prank(attester);
        reg.attest(H1, V, LOC, PROF);
        vm.expectEmit(address(reg));
        emit ReportRevoked(H1, true);
        vm.prank(attester);
        reg.setRevoked(H1, true);
        (, bool revoked,,,,) = reg.verify(H1);
        assertTrue(revoked);
        vm.prank(attester);
        reg.setRevoked(H1, false);
        (, revoked,,,,) = reg.verify(H1);
        assertFalse(revoked);
    }

    function test_revoke_reverts() public {
        vm.prank(attester);
        vm.expectRevert(SCRReportRegistry.UnknownReport.selector);
        reg.setRevoked(H1, true);
        vm.prank(attester);
        reg.attest(H1, V, LOC, PROF);
        vm.prank(rando);
        vm.expectRevert();
        reg.setRevoked(H1, true);
    }

    function testFuzz_attestOnce(bytes32 h) public {
        vm.assume(h != bytes32(0));
        vm.startPrank(attester);
        reg.attest(h, V, LOC, PROF);
        vm.expectRevert(SCRReportRegistry.AlreadyAttested.selector);
        reg.attest(h, V, LOC, PROF);
        vm.stopPrank();
    }
}
