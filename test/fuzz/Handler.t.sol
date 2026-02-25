

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {Test , console} from "forge-std/Test.sol";
import {OSCEngine} from "../../src/OmniStableCoinEngine.sol";
import {OmniStableCoin} from "../../src/OmniStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";


contract Handler is Test {
    OSCEngine public engine;
    OmniStableCoin public osc;
    ERC20Mock weth; 
    ERC20Mock wbtc; 
    uint256 MAX_DEP = type(uint96).max;
    uint256 MIN_DEP = 1;
    MockV3Aggregator ethUsdPricefeed;
    constructor(OSCEngine _engine, OmniStableCoin _osc) {
        engine = _engine;
        osc = _osc;
        address[] memory collateralTokens = engine.getCollateralTokenAddresses();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);
        ethUsdPricefeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }
    // redeem collateral  -> You need to deposit collateral first 

    function depositCollateral (uint256 collateral , uint256 amountCollateral) public {
        ERC20Mock token = _getCollaterFromSeed(collateral);
        amountCollateral = bound(amountCollateral , MIN_DEP , MAX_DEP);
        vm.startPrank(msg.sender);
        token.mint(msg.sender , amountCollateral);
        token.approve(address(engine) , amountCollateral);
        engine.depositCollateral(address(token) , amountCollateral);
        vm.stopPrank();
    }

    // function redeemCollateral(uint256 collateral , uint256 amountCollateral) public {
    //     ERC20Mock token = _getCollaterFromSeed(collateral);
    //     uint256 maxCollateralToRedeem = engine.getCollateralDeposited(msg.sender , address(token));
    //     amountCollateral = bound(amountCollateral , 0, maxCollateralToRedeem  );
    //     if (amountCollateral == 0 || maxCollateralToRedeem == 0 ){
    //         return; 
    //     }
    //     engine.redeemCollateral(address(token) , amountCollateral);
    // }

    function mintOSC(uint256 amountOscToMint) public {
        // ERC20Mock token = _getCollaterFromSeed(collateral);
        // amountCollateral = bound(amountCollateral , MIN_DEP , MAX_DEP);
        ( uint256 oscMinted, uint256 amountCollateral) = engine.getAccountInformation(msg.sender);
        int256 maxOscToMint = (int256(amountCollateral ) / 2) - int256(oscMinted);
        if(maxOscToMint < 0 ) {
            return;
        }
        amountOscToMint = bound(amountOscToMint , 0 , uint256(maxOscToMint));
        if(amountOscToMint == 0) {
            return ; 
        }
        vm.startPrank(msg.sender);
        engine.mintOsc(amountOscToMint);

        vm.stopPrank();
    }

    function updaeCollateralPrice(uint96 newPrice) public {
        int256 newPriceInt = int256(uint256(newPrice));
        ethUsdPricefeed.updateAnswer(newPriceInt);
    }
 
    function _getCollaterFromSeed(uint256 collateralSeed) private view  returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            
            return wbtc;
        }
            else{
            return weth;
            
            }
    }
}