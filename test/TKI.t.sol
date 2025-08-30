// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@forge-std/Test.sol";
import "../src/TKI.sol";

contract TKITest is Test {
    TKI tki;
    address admin = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xC0FFEE);

    function setUp() public {
        tki = new TKI("TikTok Interest", "TKI");

        // roles for admin (so we can mint/burn/operatorTransfer in tests)
        tki.grantRole(tki.MINTER_ROLE(), admin);
        tki.grantRole(tki.BURNER_ROLE(), admin);
        tki.grantRole(tki.OPERATOR_ROLE(), admin);
    }

    function testMintBurnAndOperatorTransfer() public {
        // mint to Alice
        tki.mint(alice, 200 ether);
        assertEq(tki.balanceOf(alice), 200 ether);

        // burn some
        tki.controllerBurn(alice, 50 ether);
        assertEq(tki.balanceOf(alice), 150 ether);

        // operator transfer 25 to Bob
        tki.operatorTransfer(alice, bob, 25 ether);
        assertEq(tki.balanceOf(alice), 125 ether);
        assertEq(tki.balanceOf(bob), 25 ether);
    }

    function testActorRegistry() public {
        // default is Unset
        assertEq(uint256(tki.actorType(carol)), uint256(TKI.ActorType.Unset));

        // set creator
        tki.setActorType(carol, TKI.ActorType.Creator);
        assertEq(uint256(tki.actorType(carol)), uint256(TKI.ActorType.Creator));

        // set back to user
        tki.setActorType(carol, TKI.ActorType.User);
        assertEq(uint256(tki.actorType(carol)), uint256(TKI.ActorType.User));
    }

    function testRoleRestrictions() public {
        // Bob has no roles
        vm.startPrank(bob);
        vm.expectRevert();
        tki.mint(bob, 1);
        vm.expectRevert();
        tki.controllerBurn(bob, 0);
        vm.expectRevert();
        tki.operatorTransfer(bob, alice, 1);
        vm.stopPrank();
    }
}
