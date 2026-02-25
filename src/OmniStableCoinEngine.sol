
// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

/**
 * @title OSCEngine
 * @author omeenee
 * 
 * The system is designed to be as minimal as possible and have the tokens maintain a 1 token == $1 peg. 
 * This stable coin has the properties 
 * Exogenous Collateral 
 * Dollar-pegged
 * Algorithmically stable 
 * Our OSC should always be overcollaterized.
 * Similar to DAI if DAI had no governance , no fees and was only backed by wethand wbtc
 */
import {OmniStableCoin} from "./OmniStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/Oracles.lib.sol";
contract OSCEngine is ReentrancyGuard { 
    ////////////////////// 
    ////////ERRORS//////// 
    ///////////////////// 
    error OSCEngine__MustBeGreaterThanZero();
    error OSCEngine__UnequalAddressList();
    error OSCEngine__NoPriceFeedForTokenExist();
    error OSCEngine__FailedTransaction(); 
    error OSCEngine__RiskOfLiquidation();
    error OSCEngine__MintFailed();
    error OSCEngine__NotEnoughCollateral();
    error OSCEngine__HealthNotImproved();
    error OSCEngine__BurnFailed(uint256 balance , uint256 burnAmount);
    error OSCEngine__CannotLiquidate(uint256 healthFactor);
    //////////////////////// 
    ///Types//////
    ////////////////////// 

    using OracleLib for AggregatorV3Interface;
    //////////////////////// 
    ///STATE VARIABLES//////
    ////////////////////// 
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant CONVERSION_PRICE_DECIMAL= 1e18;
    mapping (address token=> address priceFeed) private s_priceFeeds;
    mapping (address loaner => mapping(address token =>uint256 collateralValue)) private s_loanerToCollateralValue;
    mapping(address loaner => uint256 amountOSCminted) private s_OSCMinted;
    address[] private s_collateralTokens;
    OmniStableCoin private immutable i_osc;

    event CollateralDeposited(address , address , uint256); 
    event CollateralRedeemed(address , address , uint256);
    modifier amountMoreThanZero(uint256 amount) {
        if (amount <= 0){
            revert OSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)){
            revert OSCEngine__NoPriceFeedForTokenExist();
        }
        _;
    }


    //////////////////////// 
    ///FUNCTIONS///////////
    ////////////////////// 

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address oscAdress
    ){

        if(tokenAddresses.length != priceFeedAddresses.length){
            revert OSCEngine__UnequalAddressList();
        }
        for (uint8 i = 0 ; i < tokenAddresses.length; i++){
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_osc = OmniStableCoin(oscAdress);
    }

    //////////////////////// 
    ///EXTERNALFUNCTIONS////
    //////////////////////
    function depositCollateralAndMintOsc(address tokenCollateralAddress , uint256 amountCollateral,
    uint256 amountOSCtoMint
) external {
    depositCollateral(tokenCollateralAddress,amountCollateral);
    mintOsc(amountOSCtoMint);

    }
    /**
     * 
     * @param tokenCollateralAddress The address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */ 
    function depositCollateral(
        address tokenCollateralAddress , uint256 amountCollateral
    ) public amountMoreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant{
        s_loanerToCollateralValue[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender , tokenCollateralAddress , amountCollateral);
        (bool success) = IERC20(tokenCollateralAddress).transferFrom(msg.sender , address(this) , amountCollateral);
        if(!success){
            revert OSCEngine__FailedTransaction();
        }

    }

    /**
     * In order to redeem collateral , you need to do the following 
     * 1. check health factor must be over 1 after collateral pulled
     */
    function redeemCollateral(address tokenCollateralAddress , uint256 amountCollateral) public  amountMoreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress)  nonReentrant{
         _redeemCollateral(tokenCollateralAddress , amountCollateral , msg.sender , msg.sender);
      _revertIfHealthFactorIsBreached(msg.sender);

    }
    function redeemCollateralAndBurnOsc(
        address tokenCollateralAddress , uint256 amountCollateral , uint256 oscToBeBurnt
    ) external{
        burnOsc(msg.sender , oscToBeBurnt);
        redeemCollateral(tokenCollateralAddress , amountCollateral);
    }
    function burnOsc(address minter , uint256 oscToBeBurnt) public amountMoreThanZero(oscToBeBurnt) nonReentrant{ 
        _burnOsc(oscToBeBurnt , minter , msg.sender);
         _revertIfHealthFactorIsBreached(minter);
    }

    /**
     * 
     * @param amountOSCtoMint The amount of OSC to mint
     * @notice They must have more collateralvalue than minimum threshhold
     */
    function mintOsc(
        uint256 amountOSCtoMint
    ) public amountMoreThanZero(amountOSCtoMint) nonReentrant {
         s_OSCMinted[msg.sender] += amountOSCtoMint;
        //  if they minted too much ie , the minted OSC value is bigger than their collateral value
        _revertIfHealthFactorIsBreached(msg.sender);

        bool minted = i_osc.mint(msg.sender , amountOSCtoMint);

        if (!minted) {
            revert OSCEngine__MintFailed();
        }
    }

    // if someone is under collateralized , they can be liquidated by anyone.
    /**
     * 
     * @param tokenCollateralAddress The Erc20 token to liquidate
     * @param amountCollateralToLiquidate The amount you'd like to liquidate
     * @param userToBeLiquidated The person you want to liquidate
     * This means that you can partially liquidate a user
     * 
     */
    function liquidate(address tokenCollateralAddress , uint256 amountCollateralToLiquidate , address userToBeLiquidated) external amountMoreThanZero(amountCollateralToLiquidate) nonReentrant {
        //check health factor of the user 
        uint256 healthFactor = _healthFactor(userToBeLiquidated);
        if (healthFactor >= MIN_HEALTH_FACTOR){
            revert OSCEngine__CannotLiquidate(healthFactor);
        }

        // we want to burn their osc debt 
        //and take their collateral in return 
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress , amountCollateralToLiquidate);
         //We would also give the liquidator a bonus for liquidating the user , but for simplicity we will not add that in this version
        uint256 bonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        // ADD this to bonus to the token amount to get the total amount of collateral the liquidator will receive
        uint256 totalCollateralToReceive = tokenAmountFromDebtCovered + bonus;
        //we need to burn the osc equivalent to the usd amount being covered by the liquidator
        // we need to reduce the owners collateral by the total collateral to receive
        _redeemCollateral(tokenCollateralAddress , totalCollateralToReceive , userToBeLiquidated , msg.sender);
        _burnOsc(amountCollateralToLiquidate , userToBeLiquidated , msg.sender);
        uint256 healthFactorAfter = _healthFactor(userToBeLiquidated);
        if (healthFactorAfter < MIN_HEALTH_FACTOR){
            revert OSCEngine__HealthNotImproved();
        }
        _revertIfHealthFactorIsBreached(userToBeLiquidated);

    }
    function getHealthFactor() external{ }
    
    function getCollateralTokenAddresses() external view returns (address[] memory){
        return s_collateralTokens;
    }
    
    //////////////////////// 
    ///INTERNAL FUNCTIONS////
    //////////////////////

    function _getAccountInformation(address minter) private view returns(uint256 totalOSCMinted , uint256 collateralValueInUsd){
        totalOSCMinted = s_OSCMinted[minter];
        collateralValueInUsd = getAccountCollateralValue(minter);
    }
    /**
     * 
     * Returns how close a user is to liquidation. 
     * if user goes below 1 , they are at risk of 
     * liquidation 
     */
    function _healthFactor(address minter) private view returns(uint256 healthFactor){
        //get total OSC minted
        // total collateral value
        (uint256 totalOSCMinted , uint256 collateralValueInUsd) = _getAccountInformation(minter);
        uint256 adjustedCollateralForThreshold = ( collateralValueInUsd * LIQUIDATION_THRESHOLD) /LIQUIDATION_PRECISION;
        if (totalOSCMinted != 0) {
            
        return (adjustedCollateralForThreshold * CONVERSION_PRICE_DECIMAL) / totalOSCMinted;
        }
        else{
            return type(uint256).max;
        }
        

    }
    function _revertIfHealthFactorIsBreached(address minter) internal view{
        //check health factor
        //revert if they dont have sufficient health factor
        uint256 healthFactor = _healthFactor(minter); 
        if (healthFactor < MIN_HEALTH_FACTOR){
            revert OSCEngine__RiskOfLiquidation();
        }


    }

    function _burnOsc(uint256 amountOfOSCToBurn , address onBehalfOf , address oscFrom) private amountMoreThanZero(amountOfOSCToBurn) {
  
        uint256 balance = i_osc.balanceOf(onBehalfOf);
        if(amountOfOSCToBurn > balance){

            revert OSCEngine__BurnFailed(balance , amountOfOSCToBurn);
        }
        s_OSCMinted[onBehalfOf] -= amountOfOSCToBurn;
        bool success = i_osc.transferFrom(oscFrom , address(this), amountOfOSCToBurn);
        if (!success) {
            revert OSCEngine__FailedTransaction();
        }
        i_osc.burn(amountOfOSCToBurn);
    }
    function _redeemCollateral(address tokenCollateralAddress , uint256 amountCollateral , address from , address to) private {
        
        uint256 current = s_loanerToCollateralValue[from][tokenCollateralAddress];

        if (current < amountCollateral) {
        revert OSCEngine__NotEnoughCollateral();
        }
        s_loanerToCollateralValue[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from , tokenCollateralAddress , amountCollateral);

       
        //send the collateral back to the user
        //take back the OSC if they have any minted
        bool success  = IERC20(tokenCollateralAddress).transfer(to , amountCollateral);
        if(!success){
            revert OSCEngine__FailedTransaction();
        }
    }
     //////////////////////// 
    ///PUBLIC and VIEW FUNCTIONS////
    //////////////////////

    function getTokenAmountFromUsd(address token , uint256 usdAmount) public view returns (uint256 tokenAmount){
        //get price of eth (token)
        // use the price feed to get the value of token in usd 
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_priceFeeds[token]);

        (, int256 price, , ,) = pricefeed.stalePriceCheck();
        //eg 2000usd / eth , 1000 usd worth of eth = 0.5eth
        tokenAmount = usdAmount * CONVERSION_PRICE_DECIMAL / (uint256(price) * ADDITIONAL_FEED_PRECISION);

       

    }
    function getAccountCollateralValue(address minter) public view returns(uint256  totalCollateralValueInUsd){
        for(uint256 i = 0 ; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_loanerToCollateralValue[minter][token];
            totalCollateralValueInUsd += getCollateralValueInUsd(token , amount); 
        }
    }
    function getCollateralValueInUsd(address token , uint256 amount) public view returns (uint256 value){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price, , ,) = priceFeed.stalePriceCheck();
        value = ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / (CONVERSION_PRICE_DECIMAL);

    }
     function returnPriceValue(address token ) public view returns (int256 price){
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, price, , ,) = priceFeed.stalePriceCheck();
        

    }

    function getCollateralDeposited(address user , address token) public  returns (uint256 collateralDeposited) {
        collateralDeposited = s_loanerToCollateralValue[user][token];
        
    }
    function getOSCBalance(address user) public view returns(uint256){
        return s_OSCMinted[user];
    }

    function getAccountInformation(address minter) external view returns(uint256 totalOSCMinted , uint256 collateralValueInUsd){
        return _getAccountInformation(minter);
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
    
}