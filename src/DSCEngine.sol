// SPDX-License-Identifier: MIT
// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PriceConverter} from "./PriceConverter.sol";

pragma solidity 0.8.20;

/**
 * @title DSCEngine
 * @author Cedric Ngakam
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard, PriceConverter {
    /* errors */
    error DSCEngine_MustBeMoreThanZero();
    error DSCEngine_InputLenghtNotMatch();
    error DSCEngine_AddressZeroGiven();
    error DSCEngine_NoPriceFeedFoundForTokenAddressGiven();
    error DSCEngine_TransferFailed();
    error DSCEngine_HealthFactorIsBroken();
    error DSCEngine_DSCMintFailed();
    error DSCEngine_HealthFactorAboveMinimumInLiquidation();
    error DSCEngine_HealthFactorNotImproved();

    /* type declarations */

    /* state variables */
    mapping(address tokenAddress => address priceFeedAddress) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_userCollateralDeposits;
    mapping(address user => uint256 amountDscMinted) private s_userDscMinted;
    address[] private s_collateralTokenAddresses;
    DecentralizedStableCoin private immutable i_dsc;
    uint256 private constant MINIMUM_COLLATERAL_THRESHOLD = 75; // 150%
    uint256 private constant PRECISION = 1e18;
    uint256 private constant MINIMUM_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_THRESOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus

    /* events */
    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    event CollateralRedeemed(
        address indexed from,
        address indexed liquidator,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    /* modifiers */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert DSCEngine_MustBeMoreThanZero();
        _;
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine_NoPriceFeedFoundForTokenAddressGiven();
        }
        _;
    }

    /* functions */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_InputLenghtNotMatch();
        }
        if (dscAddress == address(0)) revert DSCEngine_AddressZeroGiven();
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokenAddresses.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     *
     * @param tokenCollateralAddress the address of the token to be deposited as collateral
     * @param amountCollateral the amount of the token to be deposited as collateral
     * @param amountDscToMint the amount of DSC to mint
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice this function allows the user to redeem the collateral for DSC
     * @param tokenCollateralAddress the address of the token to be redeemed
     * @param amountCollateral the amount of the token to be redeemed
     * @param amountDscToBurn the amount of DSC to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /**
     * @param tokenCollateralAddress the address of the token to be deposited as collateral
     * @param amountCollateral the amount of the token to be deposited as collateral
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_userCollateralDeposits[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        (bool success) = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) revert DSCEngine_TransferFailed();
    }

    /**
     *
     * @param amountDscToMint the amount of DSC to mint
     * @notice must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_userDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) revert DSCEngine_DSCMintFailed();
    }

    function redeemCollateral(address collateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, collateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(msg.sender, msg.sender, amount);
    }

    /**
     * @param collateralAddress the address of the erc20 token to be redeemed
     * @param user the address of the user who has broken the health factor
     * @param debtToCover the amount of DSC to burn
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHF = _healthFactor(user);
        if (startingHF >= MINIMUM_HEALTH_FACTOR) revert DSCEngine_HealthFactorAboveMinimumInLiquidation();
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralAddress, debtToCover);
        uint256 bonnusCollateral = tokenAmountFromDebtCovered * LIQUIDATION_BONUS / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonnusCollateral;
        _redeemCollateral(user, msg.sender, collateralAddress, totalCollateralToRedeem);
        _burnDsc(user, msg.sender, debtToCover);
        uint256 endingHF = _healthFactor(user);
        if (endingHF <= startingHF) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /* Internal Functions */
    function _revertIfHealthFactorIsBroken(address user) private view {
        if (_healthFactor(user) < MINIMUM_HEALTH_FACTOR) {
            revert DSCEngine_HealthFactorIsBroken();
        }
    }

    /**
     * @notice returns the health factor of the user, if it the health factor is less than 1e18, the user is considered to be in a liquidation state
     * @param user the address of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 dscMinted, uint256 usdCollateralValue) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold =
            (usdCollateralValue * MINIMUM_COLLATERAL_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / dscMinted;
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 dscMinted, uint256 usdCollateralValue)
    {
        // 1. we get the minted DSC value
        dscMinted = s_userDscMinted[user];
        // 2. we get the collateral value
        usdCollateralValue = _getCollateralValue(user);
    }

    function _getCollateralValue(address user) public view returns (uint256 collateralValue) {
        for (uint256 i = 0; i < s_collateralTokenAddresses.length; i++) {
            address token = s_collateralTokenAddresses[i];
            uint256 amount = s_userCollateralDeposits[user][token];
            uint256 value = _getUsdValue(token, amount);
            collateralValue += value;
        }
    }

    function _redeemCollateral(
        address from,
        address liquidator,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_userCollateralDeposits[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, liquidator, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(liquidator, amountCollateral);
        if (!success) revert DSCEngine_TransferFailed();
    }

    function _burnDsc(address onBehalfOf, address dscFrom, uint256 amount) private {
        s_userDscMinted[onBehalfOf] -= amount;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amount);
        if (!success) revert DSCEngine_TransferFailed();
        i_dsc.burn(amount);
    }

    function _getUsdValue(address tokenCollateralAddress, uint256 amountCollateral) private view returns (uint256) {
        address priceFeedAddress = s_priceFeeds[tokenCollateralAddress];
        uint256 usdPrice = _getPrice(priceFeedAddress);
        return (usdPrice * amountCollateral) / PRECISION;
    }

    /* External and public View Pure Functions */

    /**
     *
     * @param tokenCollateralAddress the address of the token to get the value of
     * @param amountCollateral the amount of the token to get the value of
     */
    function getUsdValue(address tokenCollateralAddress, uint256 amountCollateral)
        public
        view
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        returns (uint256)
    {
        return _getUsdValue(tokenCollateralAddress, amountCollateral);
    }

    function getTokenAmountFromUsd(address collateralAddress, uint256 usdAmount) public view returns (uint256) {
        uint256 collateralPrice = _getPrice(collateralAddress);
        return (usdAmount * PRECISION) / collateralPrice;
    }

    function getPriceFeed(address tokenAddress) public view returns (address) {
        return s_priceFeeds[tokenAddress];
    }

    function getCollateralTokenAddresses(uint256 index) public view returns (address) {
        return s_collateralTokenAddresses[index];
    }

    function getDscAddress() public view returns (address) {
        return address(i_dsc);
    }

    function getUserCollateral(address user, address token) public view returns (uint256) {
        return s_userCollateralDeposits[user][token];
    }
}
