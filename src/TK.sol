// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * TK: Stable token for wallet balances.
 * - MINTER_ROLE: mint TK on fiat on-ramp or interest conversion
 * - BURNER_ROLE: burn TK on off-ramp/withdrawals
 * - OPERATOR_ROLE: controller can transfer without allowance during settlement
 */
contract TK is ERC20, ERC20Burnable, AccessControl, Ownable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) Ownable(_msgSender()) {
        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function controllerBurn(
        address from,
        uint256 amount
    ) external onlyRole(BURNER_ROLE) {
        _burn(from, amount);
    }

    // OZ v5 ERC20 uses _update internally for transfer/mint/burn
    function operatorTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        _update(from, to, amount);
    }
}
