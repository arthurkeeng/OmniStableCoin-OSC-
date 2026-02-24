// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {OmniStableCoin} from "../src/OmniStableCoin.sol";
import {OSCEngine} from "../src/OmniStableCoinEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
contract DeployOSC is Script {
    address[]  public tokenAddresses;
    address[]  public priceFeedAddresses;
    function run() external returns (OmniStableCoin , OSCEngine , HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        ( address wethUsdPriceFeed,
        address wbtcUsdPriceFeed,
        address weth,
        address wbtc,
        uint256 deployerKey) = helperConfig.activeNetworkConfig();
        tokenAddresses =[weth , wbtc];
        priceFeedAddresses =[wethUsdPriceFeed, wbtcUsdPriceFeed];
        vm.startBroadcast(deployerKey);
        OmniStableCoin omniStableCoin = new OmniStableCoin();
        OSCEngine oscEngine = new OSCEngine(tokenAddresses,priceFeedAddresses , address(omniStableCoin));
        omniStableCoin.transferOwnership(address(oscEngine));
        vm.stopBroadcast();
        return (omniStableCoin , oscEngine , helperConfig);
    }
}