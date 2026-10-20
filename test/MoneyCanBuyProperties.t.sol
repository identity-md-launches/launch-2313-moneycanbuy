// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MoneyCanBuy} from "../src/MoneyCanBuy.sol";

/// @dev Stand-in for the launch factory: the token is created inside one call, so the whole supply
/// lands on this contract, and the factory then forwards it the way a launch does.
contract PropertiesFactory {
    function deploy() external returns (MoneyCanBuy) {
        return new MoneyCanBuy();
    }

    function forward(MoneyCanBuy token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

/// @dev Stateless properties and pinned edges not covered by MoneyCanBuy.t.sol.
contract MoneyCanBuyPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MoneyCanBuy private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new MoneyCanBuy();
    }

    function test_supplyIsExactlyTenToTheTwentySeven() public view {
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
    }

    function test_launchSharesOfTheSupplyDivideExactly() public pure {
        // 10% swarm, 2% + 8% split of it, 50% pool, 40% remainder: no rounding dust in minor units.
        assertEq((SUPPLY * 1_000) / 10_000 * 10_000, SUPPLY * 1_000);
        assertEq((SUPPLY * 200) / 10_000 + (SUPPLY * 800) / 10_000, (SUPPLY * 1_000) / 10_000);
        assertEq((SUPPLY * 5_000) / 10_000, 500_000_000 ether);
        assertEq(SUPPLY - (SUPPLY * 1_000) / 10_000 - (SUPPLY * 5_000) / 10_000, 400_000_000 ether);
    }

    function test_maxMinusOneAllowanceIsFiniteAndDecrements() public {
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
    }

    function test_infiniteAllowanceStillCannotOverdrawBalance() public {
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 6 ether);
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.allowance(alice, spender), type(uint256).max);
    }

    function test_selfApprovalLetsHolderUseTransferFrom() public {
        token.approve(address(this), 3 ether);
        assertTrue(token.transferFrom(address(this), alice, 3 ether));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 3 ether);
    }

    function test_transferFromZeroAddressOwnerReverts() public {
        // No one can hold an allowance from address(0); the spend check fails first.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
    }

    function test_zeroAddressCannotApprove() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(spender, 1);
    }

    function test_zeroAddressCannotTransferEvenZero() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_tokensSentToTheTokenContractAreStuckButCounted() public {
        token.transfer(address(token), 1 ether);
        assertEq(token.balanceOf(address(token)), 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
        // The token has no function that moves its own balance; nobody can take it out.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1 ether));
        vm.prank(alice);
        token.transferFrom(address(token), alice, 1 ether);
    }

    function test_approveDoesNotEmitTransferAndTransferFromDoesNotEmitApproval() public {
        vm.recordLogs();
        token.approve(spender, 7);
        vm.prank(spender);
        token.transferFrom(address(this), alice, 7);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], keccak256("Approval(address,address,uint256)"));
        assertEq(logs[1].topics[0], keccak256("Transfer(address,address,uint256)"));
    }

    function test_factoryDeploymentGivesNothingToTheTestOrOrigin() public {
        PropertiesFactory factory = new PropertiesFactory();
        vm.prank(alice, bob);
        MoneyCanBuy launched = factory.deploy();
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(alice), 0);
        assertEq(launched.balanceOf(bob), 0);
        // The factory holds no allowance-granting power over anyone else afterwards.
        vm.prank(address(factory));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(factory), 0, 1)
        );
        launched.transferFrom(alice, address(factory), 1);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferToAnyNonZeroAddressIsExact(address to, uint256 rawAmount) public {
        to = address(uint160(bound(uint160(to), 1, type(uint160).max)));
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 before = token.balanceOf(to);
        assertTrue(token.transfer(to, amount));
        if (to == address(this)) {
            assertEq(token.balanceOf(to), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), before + amount);
            assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_thirdPartyCannotMoveFundsWithoutAllowance(address caller, uint256 rawAmount) public {
        vm.assume(caller != address(this));
        uint256 amount = bound(rawAmount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, caller, 0, amount));
        vm.prank(caller);
        token.transferFrom(address(this), caller, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitTransfersEqualOneTransfer(uint256 rawA, uint256 rawB) public {
        uint256 a = bound(rawA, 0, SUPPLY);
        uint256 b = bound(rawB, 0, SUPPLY - a);
        token.transfer(alice, a);
        token.transfer(alice, b);
        assertEq(token.balanceOf(alice), a + b);
        assertEq(token.balanceOf(address(this)), SUPPLY - a - b);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveIsIdempotentAndLastWriteWins(uint256 first, uint256 second) public {
        token.approve(spender, first);
        token.approve(spender, first);
        assertEq(token.allowance(address(this), spender), first);
        token.approve(spender, second);
        assertEq(token.allowance(address(this), spender), second);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_partialSpendsNeverExceedApproval(uint256 rawApproval, uint256 rawFirst, uint256 rawSecond)
        public
    {
        uint256 approval = bound(rawApproval, 1, SUPPLY);
        uint256 first = bound(rawFirst, 0, approval);
        uint256 second = bound(rawSecond, approval - first + 1, SUPPLY + 1);
        token.approve(spender, approval);
        vm.startPrank(spender);
        token.transferFrom(address(this), alice, first);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval - first, second)
        );
        token.transferFrom(address(this), alice, second);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), first);
        assertLe(token.balanceOf(alice), approval);
    }
}

/// @dev Launch-shaped handler: the factory forwards the swarm share to a distributor, which pays
/// claimants, and holders then trade among themselves and arbitrary fuzzed addresses. Ghost
/// variables track every address that ever held tokens, so conservation is checked over all of them.
contract LaunchHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MoneyCanBuy public immutable token;
    PropertiesFactory public immutable factory;
    address public immutable distributor;
    address[] public actors;
    address[] public holders;
    mapping(address => bool) private seen;

    uint256 public ghostDistributorReceived;
    uint256 public ghostDistributorPaid;
    uint256 public ghostMaxAllowanceDecreases;

    constructor() {
        factory = new PropertiesFactory();
        token = factory.deploy();
        distributor = makeAddr("launch distributor");
        actors.push(makeAddr("launch remainder"));
        actors.push(makeAddr("launch pool"));
        actors.push(makeAddr("launch trader one"));
        actors.push(makeAddr("launch trader two"));
        actors.push(address(token));
        _track(address(factory));
        _track(distributor);
        for (uint256 i; i < actors.length; ++i) {
            _track(actors[i]);
        }

        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        assertTrue(factory.forward(token, distributor, swarm));
        ghostDistributorReceived = swarm;
        assertTrue(factory.forward(token, actors[1], (SUPPLY * 5_000) / 10_000));
        assertTrue(factory.forward(token, actors[0], token.balanceOf(address(factory))));
    }

    function holderCount() external view returns (uint256) {
        return holders.length;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function claim(uint256 claimantSeed, address fresh, uint256 amountSeed) external {
        address claimant = _target(claimantSeed, fresh);
        uint256 available = token.balanceOf(distributor);
        uint256 amount = bound(amountSeed, 0, available);
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, amount));
        ghostDistributorPaid += amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, address fresh, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = _target(toSeed, fresh);
        uint256 balance = token.balanceOf(from);
        uint256 amount = bound(amountSeed, 0, balance + 1);
        uint256 toBefore = token.balanceOf(to);

        vm.prank(from);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(ok, amount <= balance, "transfer outcome");
        if (ok && from != to) {
            assertEq(token.balanceOf(from), balance - amount, "sender debit");
            assertEq(token.balanceOf(to), toBefore + amount, "recipient credit");
        } else {
            assertEq(token.balanceOf(from), balance, "failed or self transfer moved funds");
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = infinite ? type(uint256).max : bound(amountSeed, 0, SUPPLY);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        assertEq(token.allowance(owner, spender), amount);
    }

    function transferFrom(uint256 spenderSeed, uint256 ownerSeed, uint256 toSeed, address fresh, uint256 amountSeed)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address owner = actors[ownerSeed % actors.length];
        address to = _target(toSeed, fresh);
        uint256 allowance = token.allowance(owner, spender);
        uint256 balance = token.balanceOf(owner);
        uint256 cap = allowance < balance ? allowance : balance;
        uint256 amount = bound(amountSeed, 0, cap + 1);

        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(ok, amount <= allowance && amount <= balance, "transferFrom outcome");
        uint256 allowanceAfter = token.allowance(owner, spender);
        if (allowance == type(uint256).max) {
            if (allowanceAfter != allowance) ghostMaxAllowanceDecreases++;
        } else {
            assertEq(allowanceAfter, ok ? allowance - amount : allowance, "allowance accounting");
        }
    }

    function _target(uint256 seed, address fresh) private returns (address to) {
        if (seed % 3 == 0 && fresh != address(0) && fresh != distributor && fresh.code.length == 0) {
            to = fresh;
        } else {
            to = actors[seed % actors.length];
        }
        _track(to);
    }

    function _track(address account) private {
        if (!seen[account]) {
            seen[account] = true;
            holders.push(account);
        }
    }
}

contract MoneyCanBuyLaunchInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    LaunchHandler private handler;
    MoneyCanBuy private token;

    function setUp() public {
        handler = new LaunchHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = LaunchHandler.claim.selector;
        selectors[1] = LaunchHandler.transfer.selector;
        selectors[2] = LaunchHandler.approve.selector;
        selectors[3] = LaunchHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_supplyIsFixedAndFullyAccountedForAcrossEveryHolder() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        uint256 n = handler.holderCount();
        for (uint256 i; i < n; ++i) {
            sum += token.balanceOf(handler.holders(i));
        }
        assertEq(sum, SUPPLY, "balances over every holder differ from supply");
        assertEq(token.balanceOf(address(0)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_distributorPaysOutExactlyWhatItReceived() public view {
        assertEq(
            token.balanceOf(handler.distributor()),
            handler.ghostDistributorReceived() - handler.ghostDistributorPaid(),
            "distributor balance drifted"
        );
        assertLe(handler.ghostDistributorPaid(), (SUPPLY * 1_000) / 10_000);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_factoryKeepsNothingAndHasNoReach() public view {
        assertEq(token.balanceOf(address(handler.factory())), 0);
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; ++i) {
            assertEq(token.allowance(handler.actors(i), address(handler.factory())), 0);
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_unlimitedAllowanceNeverDecreases() public view {
        assertEq(handler.ghostMaxAllowanceDecreases(), 0);
    }
}
