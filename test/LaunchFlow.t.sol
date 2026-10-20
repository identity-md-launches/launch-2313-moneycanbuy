// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MoneyCanBuy} from "../src/MoneyCanBuy.sol";

/// @dev Test-only stand-in for deployment and token forwarding, not a pool implementation.
contract TokenFactoryHarness {
    function deploy(bytes32 salt) external returns (MoneyCanBuy) {
        return new MoneyCanBuy{salt: salt}();
    }

    function forward(MoneyCanBuy token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract LaunchFlowTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_create2MintsWholeSupplyToFactoryAndMatchesPredictedAddress() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("test deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff), address(factory), salt, keccak256(type(MoneyCanBuy).creationCode)
                        )
                    )
                )
            )
        );

        address caller = makeAddr("test factory caller");
        address origin = makeAddr("test transaction origin");
        vm.prank(caller, origin);
        MoneyCanBuy token = factory.deploy(salt);

        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(origin), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function test_launchForwardingClaimsAndPoolTransfersHaveNoFeesOrRestrictions() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        MoneyCanBuy token = factory.deploy(keccak256("test launch flow"));
        address distributor = makeAddr("test distributor");
        address pool = makeAddr("test pool transfer endpoint");
        address remainderRecipient = makeAddr("test remainder recipient");
        address claimant = makeAddr("test claimant");
        address trader = makeAddr("test trader");

        // The launch factory, not the token constructor, makes these allocations.
        uint256 swarm = SUPPLY / 10;
        uint256 liquidity = SUPPLY / 2;
        uint256 remainder = SUPPLY - swarm - liquidity;
        assertTrue(factory.forward(token, distributor, swarm));
        assertTrue(factory.forward(token, pool, liquidity));
        assertTrue(factory.forward(token, remainderRecipient, remainder));
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.balanceOf(remainderRecipient), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarm);

        // Exercise both token-transfer directions. This does not simulate AMM pricing or settlement.
        uint256 traded = 1_234 ether;
        vm.prank(pool);
        assertTrue(token.transfer(trader, traded));
        assertEq(token.balanceOf(trader), traded);
        assertEq(token.balanceOf(pool), liquidity - traded);
        vm.prank(trader);
        assertTrue(token.transfer(pool, traded));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), liquidity);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(claimant) + token.balanceOf(pool) + token.balanceOf(remainderRecipient), SUPPLY);
    }

    function test_sameCreate2SaltCannotReinitializeAnExistingToken() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        bytes32 salt = keccak256("test unique salt");
        MoneyCanBuy token = factory.deploy(salt);
        address holder = makeAddr("test holder");
        factory.forward(token, holder, SUPPLY);

        vm.expectRevert();
        factory.deploy(salt);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
