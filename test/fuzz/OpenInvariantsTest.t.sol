

// What are our invariants?

// 1. The total supply of osc should be less than the total value of collateral in the system. (overcollateralization)
// 2. Getter view functions should not revert.

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {Test , console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployOSC} from "../../script/DeployOSC.s.sol";
import {OSCEngine} from "../../src/OmniStableCoinEngine.sol";
import {OmniStableCoin} from "../../src/OmniStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Handler} from "./Handler.t.sol";
contract InvariantsTest is StdInvariant , Test {
    DeployOSC deployer;
    OSCEngine engine;
    OmniStableCoin osc;
    HelperConfig config ; 
    address weth;
    address wbtc;
   
   function setUp() public {
    deployer = new DeployOSC();
    (osc , engine , config) = deployer.run();
    (,,weth, wbtc,
    ) =  config.activeNetworkConfig();
    Handler handler = new Handler(engine , osc );
    // targetContract(address(engine));
    targetContract(address(handler));

    // dont call redeem collateral until there is collateral to redeem
   }

   function invariant_protocolHaveMoreValueThanOscSupply() public view{

    // get all the osc and collateral in the system and make sure the value of collateral is greater than the value of osc

    //get the osc supply in the system 
    uint totalSupply = osc.totalSupply();
    // get weth balance in the system 
    uint wethBalance = IERC20(weth).balanceOf(address(engine));
    //get wbtc balance in the system 
    uint wbtcBalance = IERC20(wbtc).balanceOf(address(engine));
    //get the value of weth and wbtc in usd
    uint wethUsdValue = engine.getCollateralValueInUsd(weth , wethBalance);
    uint wbtcUsdValue = engine.getCollateralValueInUsd(wbtc , wbtcBalance);
    uint totalCollateralUsdValue = wethUsdValue + wbtcUsdValue;
    assert(totalCollateralUsdValue >= totalSupply);

    console.log("total supply of osc" , totalSupply);
   }

   
}