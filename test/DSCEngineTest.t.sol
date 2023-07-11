// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "forge-std/Test.sol";
import "../src/DSCEngine.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

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
    MockERC20FailedTransfer public mockERC20Fail;
    address public WETH;
    address public WBTC;
    address public dai;
    address public randomUser;

    function setUp() public {
        mainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        //add WETH and WBTC token address to tokenAddresses array
        address[] memory tokenAddresses = new address[](3);

        mockERC20Fail = new MockERC20FailedTransfer();

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

        //deploy stablecoin and pass to dsc engine
        address dsc = deployCode("StableCoin.sol");

        engine = new DSCEngine(tokenAddresses, priceFeedAddresses, dsc);

        dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        randomUser = makeAddr("random");
    }

    //DepositCollateral tests
    function test_NotAllowedToken() public {
        deal(dai, randomUser, 1 ether);
        vm.startPrank(randomUser);
        IERC20(WETH).approve(address(engine), 0);
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
        uint256 depositedAmount = engine.getCollateralAmount(WETH);
        vm.stopPrank();
        assertEq(depositedAmount, 0.5 ether);
    }

    function test_collateralDepositTransferFailed() public {
        deal(address(mockERC20Fail), randomUser, 1 ether);
        vm.startPrank(randomUser);
        IERC20(address(mockERC20Fail)).approve(address(engine), 0.5 ether);
        vm.expectRevert(TransferFailed.selector);
        engine.depositCollateral(address(mockERC20Fail), 0.5 ether);
        uint256 depositedAmount = engine.getCollateralAmount(address(mockERC20Fail));
        vm.stopPrank();
        assertEq(depositedAmount, 0);
    }
}
