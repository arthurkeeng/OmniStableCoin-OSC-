
// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;
import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";


contract HelperConfig is Script {
    uint8 private constant DECIMAL = 8;
    int256 private constant INITIAL_PRICE_ANSWER_ETH = 2000e8;
    int256 private constant INITIAL_PRICE_ANSWER_BTC = 1000e8;
    struct NetworkConfig{
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;
    constructor(){
        if (block.chainid == 11155111){
            activeNetworkConfig = getSepoliaEthConfig();
        }
        else{
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }


    function getSepoliaEthConfig() public view returns(NetworkConfig memory){
        return NetworkConfig({
        wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306, // ETH / USD
            wbtcUsdPriceFeed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
             weth: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wbtc: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            deployerKey : vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns(NetworkConfig memory){
        if(activeNetworkConfig.wethUsdPriceFeed != address(0)){
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        MockV3Aggregator ethUsdAggregator = new MockV3Aggregator(DECIMAL , INITIAL_PRICE_ANSWER_ETH);
        ERC20Mock wethMock = new ERC20Mock();
        MockV3Aggregator btcUsdAggregator = new MockV3Aggregator(DECIMAL , INITIAL_PRICE_ANSWER_ETH);
        ERC20Mock wbtcMock = new ERC20Mock();
        vm.stopBroadcast();
        return NetworkConfig(
            {
             wethUsdPriceFeed : address(ethUsdAggregator),
             wbtcUsdPriceFeed:address(btcUsdAggregator),
             weth : address(wethMock),
             wbtc :address(wbtcMock),
             deployerKey : 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6
            }
        );
    }
}