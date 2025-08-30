// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./TK.sol";
import "./TKI.sol";

/**
 * Minimal ERC-7710 validator adapter.
 * Plug this into MetaMask Delegation Toolkit (or your validator service).
 */
interface IDelegationValidator {
    function isDelegationValid(
        address delegator,
        address token,
        bytes4 selector, // ERC20.transfer selector
        uint256 amount,
        bytes calldata delegation
    ) external view returns (bool);

    function hashDelegation(
        bytes calldata delegation
    ) external view returns (bytes32);
}

/**
 * RevenueController:
 * - Tracks index-based accrual for TKI (rebate).
 * - Queues clap/gift intents WITH stored delegations + reservations.
 * - AML approval flips intents to executable.
 * - Settles: executes approved intents via operator transfers, converts creators’ TKI->TK.
 */
contract RevenueController is Ownable, ReentrancyGuard {
    // ───────── Configurable constants ─────────
    uint256 public constant BPS = 10_000; // 100% = 10_000 bps
    uint256 public secondsPerMonth = 30 days; // “month” for pro-rating
    uint256 public accrualInterval = 1 days; // min gap between index bumps
    uint256 public settlementPeriod = 7 days; // epoch length
    uint256 public tkiPerTkRatio = 100; // 100 TKI : 1 TK
    uint256 public maxRebateMonthlyBps; // safety cap (e.g., 1000 = 10%)
    uint256 public rebateMonthlyBps; // e.g., 200 = 2%

    // Optional promo: bonus TKI on fiat on-ramp (0 = disabled)
    uint256 public onRampTkiPerTk = 0;

    // ───────── Tokens & validator ─────────
    TK public immutable tk;
    TKI public immutable tki;
    IDelegationValidator public validator;

    // ───────── Index state (Compound-like) ─────────
    uint256 public globalIndex; // 1e18 scale (TK interest per TK)
    mapping(address => uint256) public userIndex; // last seen index per account
    uint256 public lastAccrualTimestamp; // last time globalIndex was bumped

    // ───────── Settlement timer ─────────
    uint256 public lastSettlementAt;

    // ───────── Reservation mapping (prevents overspend before settlement) ─────────
    // user => token => reserved amount
    mapping(address => mapping(address => uint256)) public reservedAmount;

    // ───────── Intent queue with stored delegations ─────────
    enum IntentKind {
        Clap,
        Gift
    }
    struct Intent {
        address from; // fan
        address to; // creator
        address token; // TK or TKI
        uint256 amount;
        IntentKind kind; // Clap (TKI) / Gift (TK)
        bytes delegation; // raw ERC-7710 delegation payload (stored)
        bytes32 delegationHash;
        uint64 createdAt;
        bool approved; // AML flag
        bool settled; // executed at settlement
    }
    Intent[] public intents; // index IS the ID

    // ───────── Events ─────────
    event ParametersUpdated();
    event DelegationValidatorSet(address indexed validator);
    event Accrued(uint256 deltaIndex, uint256 newGlobalIndex, uint256 at);
    event IntentSubmitted(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        address token,
        uint256 amount,
        IntentKind kind,
        bytes32 delegationHash
    );
    event IntentApproval(uint256 indexed id, bool approved);
    event IntentSettled(uint256 indexed id);
    event CreatorSettled(
        address indexed creator,
        uint256 tkiBurned,
        uint256 tkMinted
    );

    constructor(
        address _tk,
        address _tki,
        address _validator,
        uint256 _rebateMonthlyBps,
        uint256 _maxRebateMonthlyBps
    ) Ownable(_msgSender()) {
        require(_tk != address(0) && _tki != address(0), "bad token");
        tk = TK(_tk);
        tki = TKI(_tki);
        validator = IDelegationValidator(_validator);
        maxRebateMonthlyBps = _maxRebateMonthlyBps;
        _setRebateMonthlyBps(_rebateMonthlyBps);
        lastAccrualTimestamp = block.timestamp;
        lastSettlementAt = block.timestamp;
    }

    // ───────── Admin setters ─────────
    function setDelegationValidator(address _validator) external onlyOwner {
        validator = IDelegationValidator(_validator);
        emit DelegationValidatorSet(_validator);
    }

    function setMaxRebateMonthlyBps(uint256 v) external onlyOwner {
        maxRebateMonthlyBps = v;
        emit ParametersUpdated();
    }

    function setSecondsPerMonth(uint256 v) external onlyOwner {
        require(v > 0, "zero");
        secondsPerMonth = v;
        emit ParametersUpdated();
    }

    function setAccrualInterval(uint256 v) external onlyOwner {
        require(v > 0, "zero");
        accrualInterval = v;
        emit ParametersUpdated();
    }

    function setSettlementPeriod(uint256 v) external onlyOwner {
        require(v > 0, "zero");
        settlementPeriod = v;
        emit ParametersUpdated();
    }

    function setTkiPerTkRatio(uint256 v) external onlyOwner {
        require(v > 0, "zero");
        tkiPerTkRatio = v;
        emit ParametersUpdated();
    }

    function setOnRampTkiPerTk(uint256 v) external onlyOwner {
        onRampTkiPerTk = v;
        emit ParametersUpdated();
    }

    function setRebateMonthlyBps(uint256 v) external onlyOwner {
        _setRebateMonthlyBps(v);
    }

    function _setRebateMonthlyBps(uint256 v) internal {
        require(v <= maxRebateMonthlyBps, "rebate>max");
        rebateMonthlyBps = v;
        emit ParametersUpdated();
    }

    // ───────── View helpers for UI (no state changes) ─────────
    function currentIndex() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastAccrualTimestamp;
        if (elapsed == 0) return globalIndex;
        // Δindex = monthlyBps * elapsed / (BPS * secondsPerMonth)
        uint256 delta = (rebateMonthlyBps * elapsed * 1e18) /
            (BPS * secondsPerMonth);
        return globalIndex + delta;
    }

    function pendingTkiOf(address account) public view returns (uint256) {
        uint256 idx = currentIndex();
        uint256 last = userIndex[account];
        if (idx <= last) return 0;
        uint256 balTk = tk.balanceOf(account);
        if (balTk == 0) return 0;
        uint256 tkInterest = (balTk * (idx - last)) / 1e18;
        return tkInterest * tkiPerTkRatio;
    }

    function clapCapacity(address account) external view returns (uint256) {
        uint256 live = tki.balanceOf(account);
        uint256 pending = pendingTkiOf(account);
        uint256 reserved = reservedAmount[account][address(tki)];
        uint256 free = live + pending;
        return free > reserved ? free - reserved : 0;
    }

    function previewCreatorPayoutTK(
        address creator
    ) external view returns (uint256) {
        uint256 totalTki = tki.balanceOf(creator) + pendingTkiOf(creator);
        if (tkiPerTkRatio == 0) return 0;
        return totalTki / tkiPerTkRatio;
    }

    // ───────── Accrual mechanics ─────────
    function pokeAccrual() public {
        uint256 elapsed = block.timestamp - lastAccrualTimestamp;
        require(elapsed >= accrualInterval, "too soon");
        if (elapsed == 0) return;
        uint256 deltaIndex = (rebateMonthlyBps * elapsed * 1e18) /
            (BPS * secondsPerMonth);
        globalIndex += deltaIndex;
        lastAccrualTimestamp = block.timestamp;
        emit Accrued(deltaIndex, globalIndex, block.timestamp);
    }

    function _accrueFor(address account) internal {
        uint256 last = userIndex[account];
        uint256 curr = globalIndex;
        if (curr == last) return;
        userIndex[account] = curr;
        uint256 bal = tk.balanceOf(account);
        if (bal == 0) return;
        uint256 tkInterest = (bal * (curr - last)) / 1e18;
        if (tkInterest == 0) return;
        tki.mint(account, tkInterest * tkiPerTkRatio);
    }

    function accrueFor(address account) external {
        if (block.timestamp - lastAccrualTimestamp >= accrualInterval) {
            pokeAccrual();
        }
        _accrueFor(account);
    }

    function accrueMany(address[] calldata accounts) external {
        if (block.timestamp - lastAccrualTimestamp >= accrualInterval) {
            pokeAccrual();
        }
        for (uint256 i = 0; i < accounts.length; i++) {
            _accrueFor(accounts[i]);
        }
    }

    // ───────── On-ramp mint (fiat reload -> TK, optional TKI bonus) ─────────
    function mintTK(address to, uint256 amount) external onlyOwner {
        tk.mint(to, amount);
        if (onRampTkiPerTk > 0) {
            tki.mint(to, amount * onRampTkiPerTk);
        }
    }

    // ───────── Reservation helper ─────────
    function _reserve(address user, address token, uint256 amount) internal {
        uint256 bal = IERC20(token).balanceOf(user);
        uint256 rsv = reservedAmount[user][token];
        require(bal >= rsv + amount, "insufficient (reserved)");
        reservedAmount[user][token] = rsv + amount;
    }

    // ───────── Submit intents (stored delegations) ─────────
    // For claps we accrue sender first so they can use fresh TKI.
    function submitClap(
        address creator,
        uint256 tkiAmount,
        bytes calldata delegation
    ) external nonReentrant returns (uint256 id) {
        require(tki.actorType(creator) == TKI.ActorType.Creator, "not creator");

        // refresh time & credit sender before reserving
        if (block.timestamp - lastAccrualTimestamp >= accrualInterval)
            pokeAccrual();
        _accrueFor(msg.sender);

        bytes4 sel = IERC20.transfer.selector; // 0xa9059cbb
        require(
            validator.isDelegationValid(
                msg.sender,
                address(tki),
                sel,
                tkiAmount,
                delegation
            ),
            "bad del"
        );

        _reserve(msg.sender, address(tki), tkiAmount);
        bytes32 h = validator.hashDelegation(delegation);

        id = intents.length;
        intents.push(
            Intent({
                from: msg.sender,
                to: creator,
                token: address(tki),
                amount: tkiAmount,
                kind: IntentKind.Clap,
                delegation: delegation,
                delegationHash: h,
                createdAt: uint64(block.timestamp),
                approved: false,
                settled: false
            })
        );

        emit IntentSubmitted(
            id,
            msg.sender,
            creator,
            address(tki),
            tkiAmount,
            IntentKind.Clap,
            h
        );
    }

    function submitGift(
        address creator,
        uint256 tkAmount,
        bytes calldata delegation
    ) external nonReentrant returns (uint256 id) {
        require(tki.actorType(creator) == TKI.ActorType.Creator, "not creator");

        bytes4 sel = IERC20.transfer.selector;
        require(
            validator.isDelegationValid(
                msg.sender,
                address(tk),
                sel,
                tkAmount,
                delegation
            ),
            "bad del"
        );

        _reserve(msg.sender, address(tk), tkAmount);
        bytes32 h = validator.hashDelegation(delegation);

        id = intents.length;
        intents.push(
            Intent({
                from: msg.sender,
                to: creator,
                token: address(tk),
                amount: tkAmount,
                kind: IntentKind.Gift,
                delegation: delegation,
                delegationHash: h,
                createdAt: uint64(block.timestamp),
                approved: false,
                settled: false
            })
        );

        emit IntentSubmitted(
            id,
            msg.sender,
            creator,
            address(tk),
            tkAmount,
            IntentKind.Gift,
            h
        );
    }

    // ───────── AML approval / cancel ─────────
    function approveIntents(
        uint256[] calldata ids,
        bool[] calldata flags
    ) external onlyOwner {
        require(ids.length == flags.length, "len");
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            require(id < intents.length, "id");
            intents[id].approved = flags[i];
            emit IntentApproval(id, flags[i]);
        }
    }

    function cancelIntent(uint256 id) external {
        require(id < intents.length, "id");
        Intent storage it = intents[id];
        require(!it.settled, "settled");
        require(it.from == msg.sender, "not owner");
        uint256 r = reservedAmount[it.from][it.token];
        require(r >= it.amount, "reserve bug");
        reservedAmount[it.from][it.token] = r - it.amount;
        it.amount = 0;
        it.approved = false;
    }

    // ───────── Settlement ─────────
    function settleEpoch(
        uint256[] calldata intentIds,
        address[] calldata creators
    ) external onlyOwner nonReentrant {
        require(
            block.timestamp >= lastSettlementAt + settlementPeriod,
            "epoch not ready"
        );

        // 1) finalize index & accrue creators
        if (block.timestamp - lastAccrualTimestamp >= accrualInterval) {
            pokeAccrual();
        }
        for (uint256 i = 0; i < creators.length; i++) {
            _accrueFor(creators[i]);
        }

        // 2) execute approved intents from the queue (operator transfers)
        for (uint256 j = 0; j < intentIds.length; j++) {
            uint256 id = intentIds[j];
            require(id < intents.length, "id");
            Intent storage it = intents[id];
            if (it.settled || !it.approved || it.amount == 0) continue;

            // optional: re-validate delegation at execution time
            bytes4 sel = IERC20.transfer.selector;
            if (
                !validator.isDelegationValid(
                    it.from,
                    it.token,
                    sel,
                    it.amount,
                    it.delegation
                )
            ) {
                continue; // revoked/expired since submission
            }

            if (it.token == address(tk)) {
                tk.operatorTransfer(it.from, it.to, it.amount);
            } else if (it.token == address(tki)) {
                tki.operatorTransfer(it.from, it.to, it.amount);
            } else {
                continue;
            }

            uint256 r = reservedAmount[it.from][it.token];
            reservedAmount[it.from][it.token] = r - it.amount;

            it.settled = true;
            emit IntentSettled(id);
        }

        // 3) convert creators' TKI -> TK at 100:1 (floored)
        for (uint256 k = 0; k < creators.length; k++) {
            address c = creators[k];
            require(tki.actorType(c) == TKI.ActorType.Creator, "not creator");
            uint256 bal = tki.balanceOf(c);
            if (bal == 0) continue;
            uint256 tkOut = bal / tkiPerTkRatio;
            if (tkOut > 0) {
                tki.controllerBurn(c, bal);
                tk.mint(c, tkOut);
                emit CreatorSettled(c, bal, tkOut);
            }
        }

        lastSettlementAt = block.timestamp;
    }
}
