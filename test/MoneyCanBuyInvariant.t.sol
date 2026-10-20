// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MoneyCanBuy} from "../src/MoneyCanBuy.sol";

/// @dev Exercises both valid and invalid actions against an independent balance/allowance model.
contract TokenHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MoneyCanBuy public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = makeAddr("invariant alice");
        actors[1] = makeAddr("invariant bob");
        actors[2] = makeAddr("invariant carol");
        actors[3] = makeAddr("invariant dave");
        token = new MoneyCanBuy();
        assertTrue(token.transfer(actors[0], SUPPLY));
        expectedBalance[actors[0]] = SUPPLY;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = _recipient(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        bool expectedSuccess = to != address(0) && amount <= expectedBalance[from];

        vm.prank(from);
        (bool success, bytes memory data) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, expectedSuccess, "transfer success disagrees with model");
        if (success) {
            assertTrue(abi.decode(data, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = _recipient(spenderSeed);
        uint256 amount = _amount(amountSeed, SUPPLY);

        vm.prank(owner);
        (bool success, bytes memory data) = address(token).call(abi.encodeCall(token.approve, (spender, amount)));
        assertEq(success, spender != address(0), "approval success disagrees with model");
        if (success) {
            assertTrue(abi.decode(data, (bool)));
            expectedAllowance[owner][spender] = amount;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = _recipient(toSeed);
        uint256 allowance = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from] < allowance ? expectedBalance[from] : allowance;
        uint256 amount = _amount(amountSeed, available);
        bool expectedSuccess = to != address(0) && amount <= expectedBalance[from] && amount <= allowance;

        vm.prank(spender);
        (bool success, bytes memory data) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        assertEq(success, expectedSuccess, "transferFrom success disagrees with model");
        if (success) {
            assertTrue(abi.decode(data, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (allowance != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        }
    }

    function _recipient(uint256 seed) private view returns (address) {
        uint256 index = seed % (actors.length + 1);
        return index == actors.length ? address(0) : actors[index];
    }

    function _amount(uint256 seed, uint256 available) private pure returns (uint256) {
        uint256 mode = seed % 5;
        if (mode == 0) return 0;
        if (mode == 1) return available;
        if (mode == 2) return available + 1;
        if (mode == 3) return type(uint256).max;
        return seed % (SUPPLY + 1);
    }
}

contract MoneyCanBuyInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    TokenHandler private handler;
    MoneyCanBuy private token;

    function setUp() public {
        handler = new TokenHandler();
        token = handler.token();

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndBalancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_allowancesMatchModelIncludingFailedTransactions() public view {
        for (uint256 i; i < 4; ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(owner, spender), handler.expectedAllowance(owner, spender));
            }
            assertEq(token.allowance(owner, address(0)), 0);
        }
    }
}
