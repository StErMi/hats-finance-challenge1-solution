# Hats Challenge #1

## How to run it

```bash
forge install
forge test
```

## Challenge findings

### `genMon` generate a new Mon with an incorrect order of properties

The struct of the `Mon` is

```solidity
  struct Mon {
    uint8 water;
    uint8 air;
    uint8 fire;
    uint8 speed;
  }
```

so the correct order when creating a new `Mon` should be

```diff
-newMon = Mon(fire, water, air, speed);
+newMon = Mon(water, air, fire, speed);
```

This is not a huge issue just because all the properties are generated with the same max not inclusive value (10). Still is an error that should be fixed.

### Pseudo randomness `randomGen`

`randomGen(uint256 i)` is a function that generates a number from 0 to to `i-1`. As the name state it's a pseudo random generator, and it's possible to predict which would be the random number generated even if the `nonce` used is private.

A contract could run the same code used by the function and if the result is not what they expect (for example a Mon that is not maxed out) it could just revert the transaction before finalizing.

### `forSale` is not resetted to `false` after swap

After a swap the `forSale` mapping should be resetted to `false` otherwise the swapped Mon will remain forever in a "sellable" state even if the new owner does not want to sell it anymore.

Scenario:

1. Bob want to sell `Mon1` so it call `game.putUpForSale(mon1);`
2. Alice want to swap `Mon2` for `Mon1` because it's much more powerful. Alice call `game.swap(address(Bob), mon2, mon1)` and the swap happen
3. Paul see the transaction and is able to swap again the Mon1 that Alice just purchased because the Mon is still "sellable". Paul call `game.swap(address(Alice), mon3, mon1)` and swap the new Alice's mon even if the not intended to sell it

### Swaps don't allow the seller to accept the transaction, favoring the buyer

Alice has a medium powerful Mon1 that want to sell, let's say a `Mon(5,5,5,5)`
Bob see that Alice has put `Mon1` for sale, and he decides to swap it with his `Mon2` that is the worst Mon available `Mon(1,1,1,1)`.
Alice cannot decide to accept the transaction and Bob gain, without losing anything, a better Mon.

### `indexInDeck` does not check if the is present in the deck

```solidity
function indexInDeck(address _owner, uint256 _monId) internal view returns(uint256 idx) {
  for (uint256 i; i < DECK_SIZE; i++) {
    if (decks[_owner][i] == _monId) {
      idx = i;
    }
  }
}
```

If the `if` statement is never true, the function will return the default value for the `idx` parameter that is `0`. So, even if no Mon with the ID `_monId` is found in the `_owner`'s deck, the function will return `0` like if the not present Mon was present in the first (0 index) position.

The function should return inside the `if` and `revert` if it arrives at the end of the `for` without finding a match.

### `swap` is vulnerable to reentrancy attack because of `_safeTransfer` and miss of following Checks-Effects-Interactions Pattern best practice or reentrancy guard

`_safeTransfer` is a function that internally call a "callback" `onERC721Received` if the `to` address is a `contract`. This is needed to be sure that the receiving address is able to handle ERC721 tokens (NFT).

The problem is that the function does not:

1. implement Reentrancy Guard
2. update the contract's state variables after the external call

Scenario the `to` is a Contract that implement the `onERC721Received` callback

1. Alice has mon1, mon2, mon3 in the deck
2. Bob deploy an `attacker` contract that implement `onERC721Received` and `join` the game with the contract. The contract has mon4, mon5, mon6 in the deck
3. Alice put for sale mon1
4. Bob call `attacker.game.swap(alice, mon4, mon1)`

when `_safeTransfer(_to, swapper, _monId2, "");` is executed, the `Game` call `attacker.onERC721Received` callback. At this point the `decks` are not yet updated (they are updated only after the second `_safeTransfer`.

This mean that inside `onERC721Received`

- `mon1` is already owned by Alice
  but
- `deck[alice][0]` = mon1
- `deck[attacker][0]` = mon4

At this point the attacker is able for example to call `game.fight()` where the game would fight with `deck[attacker][0]` that still point to `mon4` even if it has already been transferred to `Alice`.

So when the `attacker` will be defeated by the unbeatable `flagholder` the game will burn `mon4` that is currently owned (because it has been transferred) by `Alice` and not by the `attacker`. Note that `_burn` is a low level instruction that is not checking who's the owner of the tokenId.

After the `fight` end all the attacker mon will be burned and new mon will be replaced to the burned one.

After returning from the `onERC721Received` callback the state of the `attacker` deck is like this

- deck[0] = mon7
- deck[1] = mon8
- deck[2] = mon9

and the following instructions will be executed

```solidity
// update the decks
uint256 idx1 = indexInDeck(swapper, _monId1);
uint256 idx2 = indexInDeck(_to, _monId2);
decks[swapper][idx1] = _monId2;
decks[_to][idx2] = _monId1;
```

- `indexInDeck(swapper, mon4);` will return 0 because it will try to find a token with ID 4 inside the deck but the user deck has been replaced because the user has lost the `fight` and now it has inside mon7, mon8, mon9. Because of the problem we have discussed before, instead of reverting when it does not find a token that should be in the deck, it will return the default value of `idx` return variable that is `0`
- `indexInDeck(_to, mon1);` will return 0 because `deck[0] = mon1`
- `decks[attacker][0] = mon1` (mon1 is still alive)
- `decks[alice][0] = mon4` (mon4 has been burned because `attacker` has lost the `fight`)

So at the end of the cycle the `attacker` ends with 4 Mon instead of 3 because it has 3 new Mon (minted by `fight` to replenish the deck) + the one that has been swapped from Alice.

## How to exploit Reentrancy to gain the flag holder title

It will be a mix of all the problem we have seen, in particular we are going to use both the reentrancy problem in `swap` and the `indexInDeck` not reverting when the Mon is not present in the deck.

We could also leverage the fact that `forSell` is not updated, but it's not relevant because we will use different addresses to exploit it. In a normal scenario, we could use the `forSell` exploit to gain access to other user's Mon that have been put for sale at least one time.

What we do is:

1. we create an `Exploiter` smart contract that is able to interact with the `game`. The smart contract is inheriting from `IERC721Receiver` and implementing the `onERC721Received` callback. This callback will be called automatically by the `game` during a `swap` operation.

Inside the callback, we are just going to call `game.fight();`. If the callback has been called because of `exploiter.swap(alice, monOfAttackInPos0, monOfAliceInPos0)` it will make the attacker attack with `monOfAttackInPos0` in position 0 so the `game` will burn the Mon that after the callback will be transferred to Alice.

After the end of `swap` the Exploiter, contract will own 4 different Mons (3 new Mons after `fight` + 1 Mon from Alice)

2. Use two different accounts to join the game and fill their decks. After that, put all the Mons for sale
3. Make the `exploiter` join the game and fill its deck and put all the Mons for sale.
4. Execute `exploiter.swap(address(attacker2), 9, 3);` to leverage the reentrancy exploit. At the end of each `swap` the `exploiter` contract will have the Mon balance increased by 1 (as explained before)
5. Keep executing the exploit until you have at least 7 mon before starting the fight. This is important because after the fight the game will check if the attacker (you) have more tokens compared to the flag holder. If so you (attacker) will become the flag holde!. As soon as `attacker2` has finished the swappable Mons (that are burned each time the swap happen because of the `fight`) start using `attacker3` Mons.
6. Profit and enjoy being the Flag Holder! (well not you but your exploit contract :D
