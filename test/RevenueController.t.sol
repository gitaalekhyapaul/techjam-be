// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";
import "../src/TK.sol";
import "../src/TKI.sol";
import "../src/RevenueController.sol";

// Lightweight in-file mock validator (accept-all by default)
contract MockValidator is IDelegationValidator {
    mapping(bytes32 => bool) public overrideValid; // optional override per-hash

    function isDelegationValid(
        address,
        address,
        bytes4,
        uint256,
        bytes calldata delegation
    ) external view returns (bool) {
        bytes32 h = keccak256(delegation);
        if (overrideValid[h]) return true;
        // default: accept
        return true;
    }

    function hashDelegation(
        bytes calldata delegation
    ) external pure returns (bytes32) {
        return keccak256(delegation);
    }

    // helper to set allow-list if you want negative tests
    function setValid(bytes32 h, bool v) external {
        overrideValid[h] = v;
    }
}

contract RevenueControllerTest is Test {
    TK tk;
    TKI tki;
    RevenueController rc;
    MockValidator mv;

    address owner = address(this);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address creator = address(0xC0FFEE);

    function setUp() public {
        // Deploy tokens
        tk = new TK("TikTok USD", "TK");
        tki = new TKI("TikTok Interest", "TKI");

        // Deploy mock validator + controller (2% monthly, cap 10%)
        mv = new MockValidator();
        rc = new RevenueController(
            address(tk),
            address(tki),
            address(mv),
            200,
            1000
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
        vm.warp(block.timestamp + 15 days);
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

    // ---------- Intent Queue (store delegation + reserve) ----------

    function testSubmitClapStoresDelegationAndReserves() public {
        // Give Alice some TKI first (30 days at 2% on 100 TK = 200 TKI)
        vm.warp(block.timestamp + 30 days);
        rc.pokeAccrual();
        vm.prank(alice);
        rc.accrueFor(alice);
        assertEq(tki.balanceOf(alice), 200 ether);

        bytes memory del = abi.encodePacked("alice-clap-60-to-creator");
        vm.startPrank(alice);
        uint256 id = rc.submitClap(creator, 60 ether, del);
        vm.stopPrank();

        // Reservation recorded
        assertEq(rc.reservedAmount(alice, address(tki)), 60 ether);

        // Delegation bytes stored in queue
        (
            address from,
            address to,
            address token,
            uint256 amount,
            RevenueController.IntentKind kind,
            bytes memory storedDel,
            bytes32 dhash,
            ,
            bool approved,
            bool settled
        ) = rc.intents(id);

        assertEq(from, alice);
        assertEq(to, creator);
        assertEq(token, address(tki));
        assertEq(amount, 60 ether);
        assertEq(uint(kind), uint(RevenueController.IntentKind.Clap));
        assertEq(keccak256(storedDel), keccak256(del));
        assertEq(dhash, keccak256(del));
        assertTrue(!approved && !settled);
    }

    function testCancelIntentReleases() public {
        // accrue some TKI
        vm.warp(block.timestamp + 30 days);
        rc.pokeAccrual();
        vm.prank(alice);
        rc.accrueFor(alice);

        bytes memory del = abi.encodePacked("alice-clap-40");
        vm.startPrank(alice);
        uint256 id = rc.submitClap(creator, 40 ether, del);
        rc.cancelIntent(id);
        vm.stopPrank();

        assertEq(rc.reservedAmount(alice, address(tki)), 0);

        // amount zeroed
        (, , , uint256 amt, , , , , , bool settled) = rc.intents(id);
        assertEq(amt, 0);
        assertTrue(!settled);
    }

    // ---------- Settlement (execute + convert) ----------

    function testSettleEpochExecutesApprovedIntentsAndConverts() public {
        console.log("creatorTkBalance", tk.balanceOf(creator));
        console.log("creatorTkiBalance", tki.balanceOf(creator));
        console.log("tkiPerTkRatio", rc.tkiPerTkRatio());
        console.log("aliceTkBalance", tk.balanceOf(alice));
        console.log("aliceTkiBalance", tki.balanceOf(alice));
        // Alice accrues 200 TKI (30 days)
        vm.warp(block.timestamp + 30 days);
        rc.pokeAccrual();
        vm.prank(alice);
        rc.accrueFor(alice);

        // She claps 120 TKI to creator (enough to convert >=1 TK at 100:1)
        bytes memory del = abi.encodePacked("alice-clap-120");
        vm.prank(alice);
        uint256 id = rc.submitClap(creator, 120 ether, del);

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

        // Reservation released
        assertEq(rc.reservedAmount(alice, address(tki)), 0);

        // After operatorTransfer, creator held 120 TKI, then 0 TKI remains
        console.log("creatorTkBalance", tk.balanceOf(creator));
        console.log("creatorTkiBalance", tki.balanceOf(creator));
        console.log("tkiPerTkRatio", rc.tkiPerTkRatio());
        console.log("aliceTkBalance", tk.balanceOf(alice));
        console.log("aliceTkiBalance", tki.balanceOf(alice));
        assertEq(tki.balanceOf(creator), 0 ether);
        assertEq(tk.balanceOf(creator), 1.2 ether);

        // Intent marked settled
        (, , , , , , , , , bool settled) = rc.intents(id);
        assertTrue(settled);
    }

    // ---------- Gift path (TK) executes via operatorTransfer ----------

    function testGiftExecutesOnSettlement() public {
        // Build gift delegation (bob -> creator, 10 TK)
        bytes memory del = abi.encodePacked("bob-gift-10-tk");

        vm.prank(bob);
        uint256 id = rc.submitGift(creator, 10 ether, del);

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
        assertEq(rc.reservedAmount(bob, address(tk)), 0);
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
