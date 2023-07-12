// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./StableCoin.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

error NeedsMoreThanZero();
error TokenAddressesAndPriceAddressesMustBeSameLength();
error InvalidTokenAddress();
error TransferFailed();
error BreaksHealthFactor(uint256 userhealthFactor);
error MintFailed();
error HealthFactorOk();
error HealthFactorNotOk();
/**
 * @title DSCEngine
 * @author
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token = $1 USD peg
 * This stablecoin has the properties:
 * - Exogenpus Collateral
 * - Dollar Pegged
 * - Algorithhmically Stable
 *
 * It is similiar to DAI if DAI has no governance, no fees, and was only backed by wETH and wBTC
 *
 * @notice This contract is the core of the decentralized stablecoin system. It handles all the logic for minting and redeeming
 * DSC, as well as depositing and withdrawing collateral.
 *
 * @notice This contract is loosely based on teh MakerDAO DSS (DAI) System.
 */

contract DSCEngine {
    /**
     *
     * State Variables *
     *
     */
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% covercollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATOR_BONUS = 10;

    mapping(address token => address priceFeed) private priceFeeds; //mapping fo token address to price feed address
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private dscMinted;

    address[] private collateralTokens;

    StableCoin private immutable dsc;

    /**
     * EVENTS
     */
    event CollateralDeposited(address indexed user, address indexed collateralTokenAddress, uint256 amount);
    event CollateralRedeemed(address indexed from, address indexed to, address indexed token, uint256 amount);

    /**
     *
     * Modifiers *
     *
     */

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (priceFeeds[token] == address(0)) {
            revert InvalidTokenAddress();
        }
        _;
    }

    ///////////////////
    /// Functions ///
    /////////////////

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert TokenAddressesAndPriceAddressesMustBeSameLength();
        }

        //set mapping of price feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            collateralTokens.push(tokenAddresses[i]);
        }
        dsc = StableCoin(dscAddress);
    }

    ///////////////////
    // External Functions
    ///////////////////

    /**
     *
     * @param tokenCollateralAddress the address of the ERC20 token deposited for collateral
     * @param amountCollateral the amount of collateral deposited i.e. how many tokens
     * @param amountDSCToMint the $amount of DSC to mint that you want i.e. 50 -> $50
     * @notice This function deposits the collateral and mints the DSC in one transaction
     */
    function depositCollateralAndMintStableCoin(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     *
     * @param tokenAddress the token address that is collateral
     * @param amountCollateral amount of collateral the user wants to redeeem
     * @param amountDSCToBurn the amount of DSC to burn
     *
     * This function burns DSC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForStableCoin(address tokenAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
    {
        _burn(amountDSCToBurn, msg.sender, msg.sender);
        _redeemCollateral(tokenAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param tokenAddress the token address of the collateral you used
     * @param amountCollateral the number of tokens/ amount you want to redeem from your collateral
     *
     * @notice This function will redeem and update the users balance themself, hence we see the msg.sender, msg.sender in _redeemCollateral function call
     */
    function redeemCollateral(address tokenAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) {
        _redeemCollateral(tokenAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amount the amount fof DSC the user wants to burn
     *
     * @notice this function is used if the user wants to reduce their own supply of DSC to fix their health ratio instead of adding more collateral
     */
    function burnDSC(uint256 amount) external moreThanZero(amount) {
        _burn(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param tokenCollateral The erc20 collateral address to liquidate from the user
     * @param userToLiquidate the user who has broken the health factor. Their _healthfactor should be below MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor
     *
     * @notice Youy can partially liquidate a user.
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function working assumes the protocol will be roughly 200% collateralized
     * @notice a known bug would be if the protocol were 100% or less collateralized then we wouldn't be able to incentize the liquidators
     */
    function liquidate(address tokenCollateral, address userToLiquidate, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
    {
        //need to check health factor of user
        uint256 startingUserFactor = _healthFactor(userToLiquidate);
        if (startingUserFactor >= MIN_HEALTH_FACTOR) {
            revert HealthFactorOk();
        }

        //we want to burn their dsc debt and take their collateral
        //ex: bad user -> $140 eth and $100 dsc
        //debtToCover = $100
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(tokenCollateral, debtToCover); //How much ETH do I need to cover $100? i.e. $100/ETH PRICE

        //give them a 10% bonus for being the liquidator
        //We should implement a future to liquidate in the event the protocol is insolvent
        //and sweep extra amounts into a treasury
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        //NEED TO BURN DSC
        //AND REDEEM

        _redeemCollateral(tokenCollateral, totalCollateralToRedeem, userToLiquidate, msg.sender);
        _burn(debtToCover, userToLiquidate, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(userToLiquidate);
        if (endingUserHealthFactor <= startingUserFactor) {
            revert HealthFactorNotOk();
        }

        //reverts if the liquidators health factor goes below standard
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    ///////////////////
    // Public Functions
    ///////////////////

    /**
     * function to deposit collateral to increase the current collateralization of position
     * i.e. a top function for a user's position
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert TransferFailed();
        }
    }

    /**
     * function mintStableCoin, a function thats mints the stablecoin
     * @param amountDSCToMint the amount of stablecoin the user would like to mint
     * @notice they most have more collateral than dsc stablecoin
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) {
        dscMinted[msg.sender] += amountDSCToMint;
        //if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert MintFailed();
        }
    }

    ///////////////////
    // Private Functions
    ///////////////////

    /**
     *
     * @param tokenAddress the token address of the collateral
     * @param amountCollateral the number of collateral tokens you want to redeem
     * @param from the person whose balance is being liquidated/or you could be the person wanting to redeem your own balance
     * @param to the liquidator
     *
     * @dev low-level private, internal function - do not call unless the function calling it checking for health factors being broken
     */
    function _redeemCollateral(address tokenAddress, uint256 amountCollateral, address from, address to) private {
        collateralDeposited[from][tokenAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenAddress, amountCollateral);
        bool success = IERC20(tokenAddress).transfer(to, amountCollateral);
        if (!success) {
            revert TransferFailed();
        }
    }
    /**
     * @dev low-level internal function, do not call unless the function calling it checking for health factors being broken
     */

    function _burn(uint256 amountDSCToBurn, address debtor, address liquidator) private {
        dscMinted[debtor] -= amountDSCToBurn;
        bool success = dsc.transferFrom(liquidator, address(this), amountDSCToBurn);
        if (!success) {
            //probably unreachable as transfer has a revert on failure in dsc
            revert TransferFailed();
        }
        dsc.burn(amountDSCToBurn);
    }

    //////////////////////////////
    // Private & Internal View & Pure Functions
    //////////////////////////////

    /**
     * Checks the health factor of a users position, i.e. do they have enough collateral
     * reverts if they do not meet the min health factor requirements
     * @param user the users address that is trying to mint or redeem
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userhealthFactor = _healthFactor(user);
        if (userhealthFactor < MIN_HEALTH_FACTOR) {
            revert BreaksHealthFactor(userhealthFactor);
        }
    }

    /**
     * @param user takes a users address
     * @return healthFactor returns a uint256 number close to 1 and it is how close to a liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256 healthFactor) {
        //total collateral value
        //total DSC minted
        (uint256 totalDSCMInted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        healthFactor = (collateralAdjustedForThreshold * PRECISION) / totalDSCMInted;
    }

    /**
     *
     * @param user the address of a user
     * @return totalDSCMinted returns the total amount of DSC stablecoin minted
     * @return collateralValueInUSD returns the total collateral value
     *
     * This is an internal function that gets the account information of a user.  It will return the users
     * total minted DSC stablecoins and their current collateral value
     */

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = dscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    // External & Public View & Pure Functions ////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITION_FEED_PRECISION);
    }

    /**
     *
     * @param user the address of the user to check their collateralValue in usd
     * @return totalCollateralValueInUSD returns the value of a user's collateral in USD
     *
     * This is a public view function that retrieves the collateral token and returns the value of that collateral in USD
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        //loop through each collateral token, get the amount they have deposited, and map it to
        // the price, to get the USD value
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            uint256 amount = collateralDeposited[user][token];
            totalCollateralValueInUSD += getUSDValue(token, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITION_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralTokenBalance(address tokenAddress) public view returns (uint256) {
        return collateralDeposited[msg.sender][tokenAddress];
    }
}
