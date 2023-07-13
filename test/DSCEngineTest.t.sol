// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/DSCEngine.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "../src/StableCoin.sol";

contract MockERC20FailedTransfer is ERC20 {
    constructor() ERC20("fail", "FT") {}

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        return false;
    }
}

contract DSCEngineTest is Test {
    using stdStorage for StdStorage;

    uint256 private mainnetFork;
    DSCEngine private engine;
    StableCoin public dsc;
    address public WETH;
    address public WBTC;
    address public dai;
    address public randomUser;

    function setUp() public {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        //add WETH and WBTC token address to tokenAddresses array
        address[] memory tokenAddresses = new address[](2);

        WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

        tokenAddresses[0] = WETH;
        tokenAddresses[1] = WBTC;

        //add priceFeeds for WETH and WBTC to priceFeedAddresses array

        address[] memory priceFeedAddresses = new address[](2);
        priceFeedAddresses[0] = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        priceFeedAddresses[1] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);

        //deploy stablecoin and pass to dsc engine
        dsc = new StableCoin();

        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(engine));

        dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        randomUser = makeAddr("random");
    }

    //Constructor Tests

    function test_revertIfPriceFeedsAndTokenAddressesDiffLengths() public {
        address[] memory priceFeedAddresses = new address[](4);
        address[] memory tokenAddresses = new address[](3);
        address dscAddr = deployCode("StableCoin.sol");
        vm.expectRevert(TokenAddressesAndPriceAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, dscAddr);
    }

    function test_InitializedStableCoin() public {
        address[] memory priceFeedAddresses = new address[](4);
        address[] memory tokenAddresses = new address[](4);
        address dscAddr = deployCode("StableCoin.sol");
        DSCEngine mockEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, dscAddr);
        console.log(mockEngine.getDSCAddress());
        assertEq(dscAddr, mockEngine.getDSCAddress());
    }

    //DepositCollateral tests
    function test_NotAllowedToken() public {
        deal(dai, randomUser, 1 ether);
        vm.startPrank(randomUser);
        vm.expectRevert(InvalidTokenAddress.selector);
        engine.depositCollateral(dai, 50);
        vm.stopPrank();
    }

    function test_IsZeroDeposit() public {
        deal(WETH, randomUser, 1 ether);
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), 0);
        vm.expectRevert(NeedsMoreThanZero.selector);
        engine.depositCollateral(WETH, 0);
        vm.stopPrank();
    }

    function test_collateralDepositedAndBalanceMatches() public {
        deal(WETH, randomUser, 1 ether);
        uint256 balance = IERC20(WETH).balanceOf(randomUser);
        assertEq(balance, 1 ether);
        uint256 transferAmount = 0.5 ether;
        assertGe(balance, transferAmount);

        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), transferAmount);
        engine.depositCollateral(WETH, transferAmount);
        assertEq(IERC20(WETH).balanceOf(address(engine)), transferAmount);
        vm.stopPrank();
    }

    function test_collateralMappingUpdatedCorrectly() public {
        deal(WETH, randomUser, 1 ether);
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), 0.5 ether);
        engine.depositCollateral(WETH, 0.5 ether);
        uint256 depositedAmount = engine.getCollateralTokenBalance(WETH);
        vm.stopPrank();
        assertEq(depositedAmount, 0.5 ether);
    }

    function test_collateralDepositTransferFailed() public {
        address[] memory tokenAddresses = new address[](3);

        MockERC20FailedTransfer mockERC20Fail = new MockERC20FailedTransfer();

        WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

        tokenAddresses[0] = WETH;
        tokenAddresses[1] = WBTC;
        tokenAddresses[2] = address(mockERC20Fail);

        //add priceFeeds for WETH and WBTC to priceFeedAddresses array

        address[] memory priceFeedAddresses = new address[](3);
        priceFeedAddresses[0] = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        priceFeedAddresses[1] = address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c);
        priceFeedAddresses[2] = makeAddr("failederc20");

        address dscAddr = deployCode("StableCoin.sol");

        DSCEngine engineWithFakeERC20 = new DSCEngine(tokenAddresses, priceFeedAddresses, dscAddr);

        deal(address(mockERC20Fail), randomUser, 1 ether);
        vm.startPrank(randomUser);
        IERC20(address(mockERC20Fail)).approve(address(engineWithFakeERC20), 0.5 ether);
        vm.expectRevert(TransferFailed.selector);
        engineWithFakeERC20.depositCollateral(address(mockERC20Fail), 0.5 ether);
        uint256 depositedAmount = engineWithFakeERC20.getCollateralTokenBalance(address(mockERC20Fail));
        vm.stopPrank();
        assertEq(depositedAmount, 0);
    }

    //mintDSC tests
    function test_MintZero() public {
        vm.prank(randomUser);
        vm.expectRevert(NeedsMoreThanZero.selector);
        engine.mintDSC(0);
    }

    //Updated dscMinted mapping with correct balance
    function test_MappingUpdatedCorrectlyUponMint() public {
        deal(WETH, randomUser, 1 ether);
        uint256 depositAmount = 0.5 ether;
        uint256 dscAmountToMint = 30;
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), depositAmount);
        engine.depositCollateral(WETH, depositAmount);
        engine.mintDSC(dscAmountToMint);
        vm.stopPrank();
        uint256 mappingBalance = engine.getDSCMinted(randomUser);
        assertEq(mappingBalance, dscAmountToMint);
    }

    //minted correct amount with good health factor
    function test_MintCorrectAmountWithGoodHealthFactor() public {
        deal(WETH, randomUser, 1 ether);
        uint256 depositAmount = 0.5 ether;
        uint256 dscAmountToMint = 30;
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), depositAmount);
        engine.depositCollateral(WETH, depositAmount);
        engine.mintDSC(dscAmountToMint);
        vm.stopPrank();
        assertEq(dscAmountToMint, dsc.balanceOf(randomUser));
    }

    //mint matches mapping and balance
    function test_MintMappingMatchesBalance() public {
        deal(WETH, randomUser, 1 ether);
        uint256 depositAmount = 0.5 ether;
        uint256 dscAmountToMint = 30;
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), depositAmount);
        engine.depositCollateral(WETH, depositAmount);
        engine.mintDSC(dscAmountToMint);
        uint256 balance = dsc.balanceOf(address(randomUser));
        uint256 mappingBalance = engine.getDSCMinted(randomUser);
        assertEq(balance, mappingBalance);
    }

    //mint with bad health factor
    function test_MintFailsWithBadHealthScore() public {}

    //mint with zero collateral
    function test_revertsWithZeroDeposit() public {}

    //DepositMintDSC

    //check that function works correctly with a normal deposit

    //Check that the user recieves the correct amount of DSC

    //Check reverts if health score not good
}
