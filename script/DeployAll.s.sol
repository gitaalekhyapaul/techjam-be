// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@forge-std/Script.sol";
import "../src/RevenueController.sol";
import "../src/TK.sol";
import "../src/TKI.sol";
import {console} from "@forge-std/console.sol";

// Dummy validator that accepts everything (optional for devnets)
contract DummyValidator is IDelegationValidator {
    function isDelegationValid(
        address,
        address,
        bytes4,
        uint256,
        bytes calldata
    ) external pure returns (bool) {
        return true;
    }

    function hashDelegation(bytes calldata d) external pure returns (bytes32) {
        return keccak256(d);
    }
}

contract DeployAll is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address creator = vm.envAddress("CREATOR_ADDR"); // set one demo creator

        vm.startBroadcast(pk);

        TK tk = new TK("TikTok USD", "TK");
        TKI tki = new TKI("TikTok Interest", "TKI");

        // Deploy validator (swap with real toolkit validator in prod)
        DummyValidator validator = new DummyValidator();

        // rebate 2% (200 bps), max 10% (1000 bps)
        RevenueController rc = new RevenueController(
            address(tk),
            address(tki),
            address(validator),
            200,
            1000
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
        console.log("Validator: ", address(validator));
    }
}
