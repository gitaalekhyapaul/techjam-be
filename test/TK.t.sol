// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@forge-std/Test.sol";
import "../src/TK.sol";

contract TKTest is Test {
    TK tk;
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        tk = new TK("TikTok USD", "TK");

        // grant roles to the test admin
        tk.grantRole(tk.MINTER_ROLE(), admin);
        tk.grantRole(tk.BURNER_ROLE(), admin);
        tk.grantRole(tk.OPERATOR_ROLE(), admin);
    }

    function testMintAndBurn() public {
        tk.mint(alice, 100 ether);
        assertEq(tk.balanceOf(alice), 100 ether);

        tk.controllerBurn(alice, 40 ether);
        assertEq(tk.balanceOf(alice), 60 ether);
    }

    function testOperatorTransfer() public {
        tk.mint(alice, 50 ether);

        // move 20 from Alice to Bob using operator role (no allowance)
        tk.operatorTransfer(alice, bob, 20 ether);
        assertEq(tk.balanceOf(alice), 30 ether);
        assertEq(tk.balanceOf(bob), 20 ether);
    }

    function testStandardTransfer() public {
        tk.mint(alice, 10 ether);

        vm.prank(alice);
        tk.transfer(bob, 3 ether);

        assertEq(tk.balanceOf(bob), 3 ether);
        assertEq(tk.balanceOf(alice), 7 ether);
    }

    function testRoleRestrictions() public {
        // fresh user cannot mint/burn/operatorTransfer
        vm.startPrank(bob);
        vm.expectRevert();
        tk.mint(bob, 1);
        vm.expectRevert();
        tk.controllerBurn(bob, 0);
        vm.expectRevert();
        tk.operatorTransfer(bob, alice, 1);
        vm.stopPrank();
    }
}
