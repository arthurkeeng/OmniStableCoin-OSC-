

// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {Test , console} from "forge-std/Test.sol";
import {DeployOSC} from "../script/DeployOSC.s.sol";
import {OmniStableCoin} from "../src/OmniStableCoin.sol";
import {OSCEngine} from "../src/OmniStableCoinEngine.sol";
import {HelperConfig} from "../script/DeployOSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
contract OSCEngineTest  is Test{
    DeployOSC deployer;
    OmniStableCoin osc; 
    OSCEngine engine; 
    HelperConfig config;
    address weth ; 
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    uint256 private constant AMOUNT_COLLATERAL = 10 ether;
    uint256 private constant AMOUNT_OSC_TO_MINT = 5 ether;
    uint256 private constant STARTING_ERC20_BALANCE = 10 ether;
    function setUp() public {
        deployer = new DeployOSC(); 
        (osc , engine , config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed,weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER , STARTING_ERC20_BALANCE);
    }
    ////////////////
    //Price Test////
    ///////////////
    function testGetUsdValue() public view {
         uint256 ehtaAmount= 10e18;
         uint256 expectedUsd = 20000e18;
         uint256 actualUsd = engine.getCollateralValueInUsd(weth , ehtaAmount);
         assertEq(expectedUsd , actualUsd);
    }


    ////////////////
    //constructor Test////
    ///////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;
    function testRevertIFTokenLengthDontMatch() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);
        vm.expectRevert(OSCEngine.OSCEngine__UnequalAddressList.selector);
        OSCEngine failedEngine = new OSCEngine(tokenAddresses , priceFeedAddresses , address(osc));
        
    }
    ////////////////
    //Collateral Test////
    ///////////////
    function testRevertCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(engine) , AMOUNT_COLLATERAL);
        vm.expectRevert(OSCEngine.OSCEngine__MustBeGreaterThanZero.selector);
        engine.depositCollateral(weth , 0);
        vm.stopPrank();

    }

    function testRedeemCollateral()  public {
        //user pranks the functions below 
        vm.startPrank(USER);
        ///user deposits collateral
        ERC20Mock(weth).approve(address(engine) , AMOUNT_COLLATERAL);
        engine.depositCollateral(weth , AMOUNT_COLLATERAL);
        uint256 collateralAfterDep = engine.getCollateralDeposited(USER , weth);
        assertEq(collateralAfterDep , 10 ether);
        engine.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 collateralAfterWith = engine.getCollateralDeposited(USER , weth);
        assertEq(collateralAfterWith , 0);
        uint256 balance = ERC20Mock(weth).balanceOf(USER);
        assertEq(balance, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testRedeemCollateralAndBurnOSC()  public {
        // prank user 
        vm.startPrank(USER);
         ERC20Mock(weth).approve(address(engine) , AMOUNT_COLLATERAL);
         engine.depositCollateralAndMintOsc(weth , AMOUNT_COLLATERAL , AMOUNT_OSC_TO_MINT);
        uint256 OSCbalance = ERC20Mock(address(osc)).balanceOf(address(engine));
        uint256 oscBalance = engine.getOSCBalance(USER);
         console.log("OSC Balance: " , OSCbalance);
         osc.approve(address(engine), AMOUNT_OSC_TO_MINT);
         engine.redeemCollateralAndBurnOsc(weth , AMOUNT_COLLATERAL , oscBalance);
        uint256 totalSupply = osc.totalSupply();
         assertEq(totalSupply ,0);


    }
}