// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin private dsc;
    DSCEngine private dscEngine;
    HelperConfig private config;
    address ethUsdFeed;
    address weth;
    address user = makeAddr("user");
    uint256 public constant INITIAL_AMOUNT = 100 ether;
    uint256 public constant DEPOSIT_AMOUNT = 10 ether;

    function setUp() public {
        DeployDSC deployDSC = new DeployDSC();
        (dsc, dscEngine, config) = deployDSC.run();
        (weth, ethUsdFeed,,,) = config.s_activeConfig();
    }

    /* Constructor Tests */
    function testRevertIfTokenLengthNotMatchPriceFeedsLength() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](2);
        vm.expectRevert(DSCEngine.DSCEngine_InputLenghtNotMatch.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function testRevertIfDscAddressIsZero() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        vm.expectRevert(DSCEngine.DSCEngine_AddressZeroGiven.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(0));
    }

    function testPriceFeedsAndCollateralTokensAreSetCorrectly() public {
        address[] memory tokenAddresses = new address[](1);
        address[] memory feedAddresses = new address[](1);
        tokenAddresses[0] = weth;
        feedAddresses[0] = ethUsdFeed;
        DSCEngine newDscEngine = new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
        assertEq(newDscEngine.getPriceFeed(weth), ethUsdFeed);
        assertEq(newDscEngine.getCollateralTokenAddresses(0), weth);
    }

    function testDscIsSetCorrectly() public view {
        assertEq(dscEngine.getDscAddress(), address(dsc));
    }

    /* Price Tests */
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsdValue = 30000e18;
        uint256 usdValue = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(usdValue, expectedUsdValue);
    }

    /* Deposit Collateral Tests */
    function testRevertDepositCollateralIfZero() public {
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
    }

    function testRevertIfDepositTokenAddressIsNotAllowed() public {
        address notAllowedToken = makeAddr("notAllowedToken");
        vm.expectRevert(DSCEngine.DSCEngine_NoPriceFeedFoundForTokenAddressGiven.selector);
        dscEngine.depositCollateral(notAllowedToken, DEPOSIT_AMOUNT);
    }

    function testUserCollateralDepositIsSetCorrectly() public {
        ERC20Mock(weth).mint(user, INITIAL_AMOUNT);
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        vm.prank(user);
        dscEngine.depositCollateral(weth, DEPOSIT_AMOUNT);
        assertEq(dscEngine.getUserCollateral(user, weth), DEPOSIT_AMOUNT);
    }

    function testIfCollateralIsTransferedToDscEngine() public {
        ERC20Mock(weth).mint(user, INITIAL_AMOUNT);
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        vm.prank(user);
        dscEngine.depositCollateral(weth, DEPOSIT_AMOUNT);
        assertEq(ERC20Mock(weth).balanceOf(address(dscEngine)), DEPOSIT_AMOUNT);
    }

    /* Mint Tests */
    function testRevertMintIfDscAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine_MustBeMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testRevertIfHealthFactorIsBrokenAfterMintingDsc() public {
        ERC20Mock(weth).mint(user, INITIAL_AMOUNT);
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        vm.prank(user);
        dscEngine.depositCollateral(weth, DEPOSIT_AMOUNT); // 10 ETH worth 20000 USD
        vm.prank(user);
        vm.expectRevert(DSCEngine.DSCEngine_HealthFactorIsBroken.selector);
        dscEngine.mintDsc(200_000 ether); // 200_000 USD
    }

    function testIfMintedDscIsTransferedToUser() public {
        ERC20Mock(weth).mint(user, INITIAL_AMOUNT);
        vm.prank(user);
        ERC20Mock(weth).approve(address(dscEngine), DEPOSIT_AMOUNT);
        vm.prank(user);
        dscEngine.depositCollateral(weth, DEPOSIT_AMOUNT); // 10 ETH worth 20000 USD
        vm.prank(user);
        dscEngine.mintDsc(10000 ether); // 10000 USD
        assertEq(ERC20Mock(address(dsc)).balanceOf(user), 10000 ether);
    }
}
