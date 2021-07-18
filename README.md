## Unicly Vaults

This repository will contain various vaults implementations sitting on top of Unicly protocol.

### UNIC to xUNIC auto staker

This vault will claim UNICs automatically and stake them in xUNIC. It is basically a regular masterchef 
except for the fact that the rewards are not minted but claimed from Unicly masterchef. Furthremore, 
because the lp tokens are not sitting inside this contract but in Unicly's masterchef, the amount of 
lp tokens each pool has is needed to be saved in the contract.

The contract is upgradable and owneable, which means the deployer will also be the owner.

Since this contract is just auto staking xUNIC it can be referred as xUNIC farmer.

#### How to run:

1. Run `npm install`
2. Add `.config.json` file with the following properties
    - `alchemyKey`
    - `coinmarketcapKey`
3. Run `npx hardhat compile`
4. Run `npx hardhat test`

Contract me for questions and clarifications