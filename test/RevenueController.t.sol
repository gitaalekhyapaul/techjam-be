// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import {DelegationManager} from "@delegation-framework/src/DelegationManager.sol";
import {Delegation, Caveat} from "@delegation-framework/src/utils/Types.sol";
import "../src/TK.sol";
import "../src/TKI.sol";
import "../src/RevenueController.sol";

// Mock DelegationManager that implements the interface for testing
// contract MockDelegationManager is IDelegationManager {
//     mapping(bytes32 => bool) public disabledDelegations_; // track disabled delegations
//     mapping(bytes32 => bool) public redeemedDelegations; // track redeemed delegations
//     mapping(bytes32 => Delegation) public storedDelegations_; // store delegations for testing

//     function redeemDelegations(
//         bytes[] calldata _permissionContexts,
//         ModeCode[] calldata /* _modes */,
//         bytes[] calldata _executionCallDatas
//     ) external {
//         // Mock implementation - just track that redemption was called
//         for (uint256 i = 0; i < _permissionContexts.length; i++) {
//             bytes32 h = keccak256(_permissionContexts[i]);
//             redeemedDelegations[h] = true;
//         }
//         // do the ERC20 transfer
//         for (uint256 i = 0; i < _executionCallDatas.length; i++) {
//             (address target, , bytes memory data) = abi.decode(
//                 _executionCallDatas[i],
//                 (address, uint256, bytes)
//             );
//             (bool success, ) = target.call(data);
//             require(success, "ERC20 transfer failed");
//         }
//     }

//     function getDelegationHash(
//         Delegation calldata _delegation
//     ) external pure returns (bytes32) {
//         return keccak256(abi.encode(_delegation));
//     }

//     function disabledDelegations(
//         bytes32 _delegationHash
//     ) external view returns (bool) {
//         return disabledDelegations_[_delegationHash];
//     }

//     // Other required functions (not used in our tests)
//     function pause() external {}

//     function unpause() external {}

//     function enableDelegation(Delegation calldata) external {}

//     function disableDelegation(Delegation calldata) external {}

//     function getDomainHash() external pure returns (bytes32) {
//         return bytes32(0);
//     }
// }

contract RevenueControllerTest is Test {
    TK tk;
    TKI tki;
    RevenueController rc;
    DelegationManager mdm;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address creator = address(0xC0FFEE);

    function setUp() public {
        // Deploy tokens
        tk = new TK("TikTok USD", "TK");
        tki = new TKI("TikTok Interest", "TKI");

        // Deploy mock delegation manager + controller (2% monthly, cap 10%)
        mdm = new DelegationManager(owner);
        rc = new RevenueController(
            address(tk), // tk
            address(tki), // tki
            address(mdm), // delegationManager
            200, // rebateMonthlyBps
            1000, // maxRebateMonthlyBps
            30 seconds, // secondsPerMonth
            1 seconds, // accrualInterval
            7 seconds // settlementPeriod
        );

        // Grant controller roles on both tokens
        tk.grantRole(tk.MINTER_ROLE(), address(rc));
        tk.grantRole(tk.BURNER_ROLE(), address(rc));
        tk.grantRole(tk.OPERATOR_ROLE(), address(rc));
        tki.grantRole(tki.MINTER_ROLE(), address(rc));
        tki.grantRole(tki.BURNER_ROLE(), address(rc));
        tki.grantRole(tki.OPERATOR_ROLE(), address(rc));

        // Mark creator
        tki.setActorType(creator, TKI.ActorType.Creator);

        // Initial TK balances via controller (on-ramp)
        rc.mintTK(alice, 100 ether);
        rc.mintTK(bob, 50 ether);
    }

    // ---------- Accrual & Views ----------

    function testPendingAndAccrual() public {
        // Advance ~15 days, bump index
        vm.warp(block.timestamp + 15 seconds);
        rc.pokeAccrual();

        // Pending for Alice: 1% of 100 TK -> 1 TK equiv -> 100 TKI
        uint256 pending = rc.pendingTkiOf(alice);
        assertApproxEqAbs(pending, 100 ether, 1e12);

        // Accrue mints TKI
        vm.prank(alice);
        rc.accrueFor(alice);
        assertApproxEqAbs(tki.balanceOf(alice), 100 ether, 1e12);

        // userIndex should now match globalIndex
        (bool ok, bytes memory data) = address(rc).staticcall(
            abi.encodeWithSignature("currentIndex()")
        );
        require(ok, "index call failed");
        uint256 idx = abi.decode(data, (uint256));
        assertEq(rc.userIndex(alice), idx);
    }

    // ---------- Delegation Storage and Intent Queue ----------

    function testStoreDelegationAndSubmitClap() public {
        // Give Alice some TKI first (30 days at 2% on 100 TK = 200 TKI)
        vm.warp(block.timestamp + 30 seconds);
        rc.pokeAccrual();
        vm.prank(alice);
        rc.accrueFor(alice);
        assertEq(tki.balanceOf(alice), 200 ether);

        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });

        // Store delegation in mock manager
        vm.startPrank(alice);
        uint256 id = rc.submitClap(creator, 60 ether, delegation);
        vm.stopPrank();
        // check that the intent is stored
        (
            address from,
            address to,
            uint256 amount,
            bytes memory delegationBytes,
            RevenueController.IntentKind kind,
            ,
            bool approved,
            bool settled
        ) = rc.intents(id);
        assertEq(from, alice);
        assertEq(to, creator);
        assertEq(amount, 60 ether);
        assertTrue(kind == RevenueController.IntentKind.Clap);
        assertTrue(!approved);
        assertTrue(!settled);

        // Decode and verify delegation
        Delegation memory decodedDelegation = abi.decode(
            delegationBytes,
            (Delegation)
        );
        assertEq(decodedDelegation.delegator, alice);
        assertEq(decodedDelegation.delegate, creator);
        assertEq(decodedDelegation.authority, bytes32(0));
        assertEq(decodedDelegation.caveats.length, 0);
        assertEq(decodedDelegation.salt, 0);
        assertEq(
            decodedDelegation.signature,
            abi.encodePacked("alice-clap-60-to-creator")
        );
    }

    function testCancelIntentReleases() public {
        // accrue some TKI
        vm.warp(block.timestamp + 30 seconds);
        rc.pokeAccrual();
        vm.startPrank(alice);
        rc.accrueFor(alice);

        // Store delegation and submit clap
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });

        uint256 id = rc.submitClap(creator, 60 ether, delegation);
        rc.cancelIntent(id);
        vm.stopPrank();

        // Check intent is cancelled
        (, , , , , , bool approved, ) = rc.intents(id);
        assertTrue(!approved);
    }

    // ---------- Settlement (execute + convert) ----------

    function testSettleEpochExecutesApprovedIntentsAndConverts() public {
        // Alice accrues 200 TKI (30 days)
        vm.warp(block.timestamp + 30 seconds);
        rc.pokeAccrual();
        vm.startPrank(alice);
        rc.accrueFor(alice);

        // Store delegation and submit clap
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });
        // Store delegation in mock manager
        uint256 id = rc.submitClap(creator, 60 ether, delegation);
        vm.stopPrank();

        // Approve intent
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        rc.approveIntents(ids, flags);

        // Advance to next epoch window
        vm.warp(block.timestamp + rc.settlementPeriod());

        // Settle including this creator
        address[] memory creators = new address[](1);
        creators[0] = creator;

        // Execute settlement
        rc.settleEpoch(ids, creators);

        // Delegated amount released
        assertEq(rc.delegatedAmount(alice, address(tki)), 0);

        // After operatorTransfer, creator held 120 TKI, then 0 TKI remains
        assertEq(tki.balanceOf(creator), 0 ether);
        assertEq(tk.balanceOf(creator), 1.2 ether);

        // Intent marked settled
        (, , , , , , , bool settled) = rc.intents(id);
        assertTrue(settled);
    }

    // ---------- Gift path (TK) executes via operatorTransfer ----------

    function testGiftExecutesOnSettlement() public {
        // Store gift delegation (bob -> creator, 10 TK)
        vm.startPrank(bob);
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: bob,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("bob-gift-10-tk")
        });
        // Store delegation in mock manager
        uint256 id = rc.submitGift(creator, 10 ether, delegation);
        vm.stopPrank();

        // Approve + settle
        uint256[] memory ids = new uint256[](1);
        ids[0] = id;
        bool[] memory flags = new bool[](1);
        flags[0] = true;
        rc.approveIntents(ids, flags);

        vm.warp(block.timestamp + rc.settlementPeriod());
        address[] memory creators = new address[](1);
        creators[0] = creator;

        uint256 creatorTkBefore = tk.balanceOf(creator);
        rc.settleEpoch(ids, creators);

        // 10 TK moved to creator
        assertEq(tk.balanceOf(creator) - creatorTkBefore, 10 ether);
        assertEq(rc.delegatedAmount(bob, address(tk)), 0);
    }

    // ---------- Delegation Management ----------

    function testDelegationRevocation() public {
        // Store delegation
        vm.startPrank(alice);
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });
        // Store delegation in mock manager
        bytes32 delegationHash = mdm.getDelegationHash(delegation);
        vm.startPrank(alice);
        rc.submitClap(creator, 60 ether, delegation);
        vm.stopPrank();
        assertEq(rc.delegatedAmount(alice, address(tki)), 60 ether);

        // Revoke delegation
        rc.revokeDelegation(delegationHash);
        vm.stopPrank();

        // Check delegation is revoked
        assertFalse(rc.storedDelegations(delegationHash));
        assertEq(rc.delegatedAmount(alice, address(tki)), 0);
    }

    function testOwnerCanRevokeDelegations() public {
        // Store delegation
        vm.prank(alice);
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });
        // Store delegation in mock manager
        bytes32 delegationHash = mdm.getDelegationHash(delegation);
        vm.startPrank(alice);
        rc.submitClap(creator, 60 ether, delegation);
        vm.stopPrank();

        // Owner revokes delegation
        rc.revokeDelegation(delegationHash);

        // Check delegation is revoked
        assertFalse(rc.storedDelegations(delegationHash));
        assertEq(rc.delegatedAmount(alice, address(tki)), 0);
    }

    function testEffectiveBalanceCalculation() public {
        // Give Alice some TKI
        vm.warp(block.timestamp + 30 days);
        rc.pokeAccrual();
        vm.startPrank(alice);
        rc.accrueFor(alice);

        uint256 balance = tki.balanceOf(alice);
        assertEq(rc.effectiveBalance(alice, address(tki)), balance);

        // Store delegation
        // Create a mock delegation for testing
        Delegation memory delegation = Delegation({
            delegate: creator,
            delegator: alice,
            authority: bytes32(0),
            caveats: new Caveat[](0),
            salt: 0,
            signature: abi.encodePacked("alice-clap-60-to-creator")
        });
        // Store delegation in mock manager
        rc.submitClap(creator, 60 ether, delegation);
        vm.stopPrank();

        // Effective balance should be reduced by delegated amount
        assertEq(rc.effectiveBalance(alice, address(tki)), balance - 60 ether);
        assertEq(rc.clapCapacity(alice), balance - 60 ether);
    }

    // ---------- Owner-only guards ----------

    function testOwnerOnlySetters() public {
        // Non-owner cannot modify parameters
        vm.prank(bob);
        vm.expectRevert();
        rc.setSettlementPeriod(3 days);

        vm.prank(bob);
        vm.expectRevert();
        rc.setRebateMonthlyBps(9999);

        // Owner can change within cap
        rc.setRebateMonthlyBps(300); // 3%
        assertEq(rc.rebateMonthlyBps(), 300);
    }
}
