// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/DSCEngine.sol";

contract DSCEngineTest is Test {
    uint256 private mainnetFork;
    DSCEngine private engine;

    function setUp() public {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        //add WETH and WBTC token address to tokenAddresses array
        address[] memory tokenAddresses = new address[](2);
        tokenAddresses[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        tokenAddresses[1] = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

        //add priceFeeds for WETH and WBTC to priceFeedAddresses array

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        priceFeedAddresses[1] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

        //deploy stablecoin and pass to dsc engine
        address dsc = deployCode("StableCoin.sol");

        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, dsc);
    }
}
