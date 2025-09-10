// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@forge-std/Script.sol";
import {DelegationManager} from "@delegation-framework/src/DelegationManager.sol";
import "../src/RevenueController.sol";
import "../src/TK.sol";
import "../src/TKI.sol";
import {console} from "@forge-std/console.sol";

contract DeployAll is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address creator = vm.envAddress("CREATOR_ADDR"); // set one demo creator

        vm.startBroadcast(pk);

        TK tk = new TK("TikTok USD", "TK");
        TKI tki = new TKI("TikTok Interest", "TKI");

        // Deploy delegation manager
        DelegationManager dm = new DelegationManager(msg.sender);

        // rebate 2% (200 bps), max 10% (1000 bps)
        RevenueController rc = new RevenueController(
            address(tk), // tk
            address(tki), // tki
            address(dm), // delegationManager
            200, // rebateMonthlyBps
            1000, // maxRebateMonthlyBps
            30 seconds, // secondsPerMonth
            1 seconds, // accrualInterval
            7 seconds // settlementPeriod
        );

        // Grant roles to controller
        tk.grantRole(tk.MINTER_ROLE(), address(rc));
        tk.grantRole(tk.BURNER_ROLE(), address(rc));
        tk.grantRole(tk.OPERATOR_ROLE(), address(rc));

        tki.grantRole(tki.MINTER_ROLE(), address(rc));
        tki.grantRole(tki.BURNER_ROLE(), address(rc));
        tki.grantRole(tki.OPERATOR_ROLE(), address(rc));

        // Mark a creator
        tki.setActorType(creator, TKI.ActorType.Creator);

        // Optional initial config tweaks
        rc.setSettlementPeriod(60 seconds);
        rc.setAccrualInterval(30 seconds);
        rc.setOnRampTkiPerTk(0); // no bonus

        vm.stopBroadcast();

        console.log("TK:  ", address(tk));
        console.log("TKI: ", address(tki));
        console.log("RC:  ", address(rc));
        console.log("DelegationManager: ", address(dm));
    }
}
