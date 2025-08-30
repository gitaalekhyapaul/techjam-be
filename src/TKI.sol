// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * TKI: Accrued “interest” points + clap token.
 * - Only creators’ TKI is converted to TK at settlement.
 * - Same roles as TK plus an actor registry (User/Creator).
 */
contract TKI is ERC20, ERC20Burnable, AccessControl, Ownable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE"); // <- fix typo
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    enum ActorType {
        Unset,
        User,
        Creator
    }
    mapping(address => ActorType) public actorType;

    event ActorTypeSet(address indexed account, ActorType actor);

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

    function operatorTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(OPERATOR_ROLE) {
        _update(from, to, amount);
    }

    function setActorType(address account, ActorType t) external onlyOwner {
        actorType[account] = t;
        emit ActorTypeSet(account, t);
    }
}
