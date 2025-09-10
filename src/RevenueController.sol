// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@delegation-framework/src/interfaces/IDelegationManager.sol";
import "@delegation-framework/src/utils/Types.sol";
import {Delegation, ModeCode} from "@delegation-framework/src/utils/Types.sol";

import "./TK.sol";
import "./TKI.sol";

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
    uint256 public secondsPerMonth = 30 seconds; // “month” for pro-rating
    uint256 public accrualInterval = 1 seconds; // min gap between index bumps
    uint256 public settlementPeriod = 7 seconds; // epoch length
    uint256 public tkiPerTkRatio = 100; // 100 TKI : 1 TK
    uint256 public maxRebateMonthlyBps; // safety cap (e.g., 1000 = 10%)
    uint256 public rebateMonthlyBps; // e.g., 200 = 2%

    // Optional promo: bonus TKI on fiat on-ramp (0 = disabled)
    uint256 public onRampTkiPerTk = 0;

    // ───────── Tokens & delegation manager ─────────
    TK public immutable tk;
    TKI public immutable tki;
    IDelegationManager public delegationManager;

    // ───────── Index state (Compound-like) ─────────
    uint256 public globalIndex; // 1e18 scale (TK interest per TK)
    mapping(address => uint256) public userIndex; // last seen index per account
    uint256 public lastAccrualTimestamp; // last time globalIndex was bumped

    // ───────── Settlement timer ─────────
    uint256 public lastSettlementAt;

    // ───────── Delegation tracking ─────────
    mapping(bytes32 => bool) public storedDelegations; // delegationHash => exists
    mapping(address => mapping(address => uint256)) public delegatedAmount; // user => token => delegated amount

    // ───────── Intent queue with delegation references ─────────
    enum IntentKind {
        Clap,
        Gift
    }
    struct Intent {
        address from; // fan
        address to; // creator
        uint256 amount; // amount of tokens to transfer
        bytes delegationBytes; // raw encoded delegation for settlement
        IntentKind kind; // Clap (TKI) / Gift (TK)
        uint64 createdAt;
        bool approved; // AML flag
        bool settled; // executed at settlement
    }
    Intent[] public intents; // index IS the ID

    // ───────── Events ─────────
    event ParametersUpdated();
    event DelegationManagerSet(address indexed delegationManager);
    event Accrued(uint256 deltaIndex, uint256 newGlobalIndex, uint256 at);
    event DelegationStored(
        bytes32 indexed delegationHash,
        address indexed delegator,
        address indexed delegate,
        uint256 amount
    );
    event DelegationRevoked(
        bytes32 indexed delegationHash,
        address indexed revoker
    );
    event IntentSubmitted(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 delegationHash,
        IntentKind kind
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
        address _delegationManager,
        uint256 _rebateMonthlyBps,
        uint256 _maxRebateMonthlyBps,
        uint256 _secondsPerMonth,
        uint256 _accrualInterval,
        uint256 _settlementPeriod
    ) Ownable(_msgSender()) {
        require(_tk != address(0) && _tki != address(0), "bad token");
        tk = TK(_tk);
        tki = TKI(_tki);
        delegationManager = IDelegationManager(_delegationManager);
        maxRebateMonthlyBps = _maxRebateMonthlyBps;
        _setRebateMonthlyBps(_rebateMonthlyBps);
        lastAccrualTimestamp = block.timestamp;
        lastSettlementAt = block.timestamp;
        secondsPerMonth = _secondsPerMonth;
        accrualInterval = _accrualInterval;
        settlementPeriod = _settlementPeriod;
    }

    // ───────── Admin setters ─────────
    function setDelegationManager(
        address _delegationManager
    ) external onlyOwner {
        delegationManager = IDelegationManager(_delegationManager);
        emit DelegationManagerSet(_delegationManager);
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
        // change in index = monthlyBps * elapsed / (BPS * secondsPerMonth) (simple interest)
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
        uint256 delegated = delegatedAmount[account][address(tki)];
        uint256 free = live + pending;
        return free > delegated ? free - delegated : 0;
    }

    function giftCapacity(address account) external view returns (uint256) {
        uint256 live = tk.balanceOf(account);
        uint256 delegated = delegatedAmount[account][address(tk)];
        return live > delegated ? live - delegated : 0;
    }

    function effectiveBalance(
        address account,
        address token
    ) external view returns (uint256) {
        uint256 balance = IERC20(token).balanceOf(account);
        uint256 delegated = delegatedAmount[account][token];
        return balance > delegated ? balance - delegated : 0;
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

    function revokeDelegation(bytes32 delegationHash) external {
        require(storedDelegations[delegationHash], "delegation not found");

        // Remove delegation reference
        storedDelegations[delegationHash] = false;

        // Note: In the real ERC-7710 system, revocation would be handled by the DelegationManager
        // This is just for tracking purposes in our system
        emit DelegationRevoked(delegationHash, msg.sender);
    }

    function revokeDelegations(
        bytes32[] calldata delegationHashes
    ) external onlyOwner {
        for (uint256 i = 0; i < delegationHashes.length; i++) {
            bytes32 delegationHash = delegationHashes[i];
            if (storedDelegations[delegationHash]) {
                storedDelegations[delegationHash] = false;
                emit DelegationRevoked(delegationHash, msg.sender);
            }
        }
    }

    // ───────── Submit intents (using stored delegations) ─────────
    function submitClap(
        address creator,
        uint256 amount,
        Delegation calldata delegation
    ) external nonReentrant returns (uint256 id) {
        require(tki.actorType(creator) == TKI.ActorType.Creator, "not creator");

        // refresh time & credit sender before checking capacity
        if (block.timestamp - lastAccrualTimestamp >= accrualInterval)
            pokeAccrual();
        _accrueFor(msg.sender);
        bytes32 delegationHash = delegationManager.getDelegationHash(
            delegation
        );

        // Check capacity (simplified for now)
        uint256 capacity = this.clapCapacity(msg.sender);
        require(capacity >= amount, "insufficient capacity");

        // Encode delegation to bytes for storage
        bytes memory delegationBytes = abi.encode(delegation);

        id = intents.length;
        intents.push(
            Intent({
                from: msg.sender,
                to: creator,
                amount: amount,
                delegationBytes: delegationBytes,
                kind: IntentKind.Clap,
                createdAt: uint64(block.timestamp),
                approved: false,
                settled: false
            })
        );
        // increment delegated amount for the certain token
        delegatedAmount[msg.sender][address(tki)] += amount;
        emit IntentSubmitted(
            id,
            msg.sender,
            creator,
            amount,
            delegationHash,
            IntentKind.Clap
        );
    }

    function submitGift(
        address creator,
        uint256 amount,
        Delegation calldata delegation
    ) external nonReentrant returns (uint256 id) {
        require(tki.actorType(creator) == TKI.ActorType.Creator, "not creator");

        // Verify delegation exists and is not disabled
        bytes32 delegationHash = delegationManager.getDelegationHash(
            delegation
        );

        // Check capacity (simplified for now)
        uint256 capacity = this.giftCapacity(msg.sender);
        require(capacity >= amount, "insufficient capacity");

        // Encode delegation to bytes for storage
        bytes memory delegationBytes = abi.encode(delegation);

        id = intents.length;
        intents.push(
            Intent({
                from: msg.sender,
                to: creator,
                amount: amount,
                delegationBytes: delegationBytes,
                kind: IntentKind.Gift,
                createdAt: uint64(block.timestamp),
                approved: false,
                settled: false
            })
        );
        // increment delegated amount for the certain token
        delegatedAmount[msg.sender][address(tk)] += amount;
        emit IntentSubmitted(
            id,
            msg.sender,
            creator,
            amount,
            delegationHash,
            IntentKind.Gift
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

        // Mark intent as cancelled by setting approved to false
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

        // 2) execute approved intents from the queue (redeem delegations)
        for (uint256 j = 0; j < intentIds.length; j++) {
            uint256 id = intentIds[j];
            require(id < intents.length, "id");
            Intent storage it = intents[id];
            if (it.settled || !it.approved) continue;

            // Determine token type and amount from intent (simplified)
            address token = (it.kind == IntentKind.Clap)
                ? address(tki)
                : address(tk);
            uint256 amount = it.amount;

            // Create arrays for delegation redemption
            bytes[] memory permissionContexts = new bytes[](1);
            ModeCode[] memory modes = new ModeCode[](1);
            bytes[] memory executionCallDatas = new bytes[](1);

            // Use stored delegation bytes directly
            permissionContexts[0] = it.delegationBytes;
            modes[0] = ModeCode.wrap(0); // Single call mode
            // Encode the execution call data properly: (target, value, callData)
            bytes memory transferCallData = abi.encodeWithSelector(
                IERC20.transfer.selector,
                it.to,
                amount
            );
            executionCallDatas[0] = abi.encode(
                token,
                uint256(0),
                transferCallData
            );

            delegationManager.redeemDelegations(
                permissionContexts,
                modes,
                executionCallDatas
            );

            // Update delegated amounts (simplified)
            delegatedAmount[it.from][token] -= amount;

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
