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
     * Errors *
     *
     */

    /**
     *
     * State Variables *
     *
     */
    uint256 private constant ADDITION_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% covercollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private priceFeeds; //mapping fo token address to price feed address
    mapping(address user => mapping(address token => uint256 amount)) private collateralDeposited;
    mapping(address user => uint256 amountDSCMinted) private dscMinted;

    address[] private collateralTokens;

    StableCoin private immutable dsc;

    /**
     * EVENTS
     */
    event CollateralDeposited(address indexed user, address indexed collateralTokenAddress, uint256 amount);

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
     * Function to deposit collateral and recieve an equivalent stablecoin amount
     */
    function depositCollateralAndMintStableCoin() external {}

    /**
     * function to deposit collateral to increase the current collateralization of position
     * i.e. a top function for a user's position
     *
     * @param tokenCollateralAddress the address of the token to deposit as collateral
     * @param amountCollateral the amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
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
     * function to redeem the collateral in exchange for the equivalent stablecoin amount
     */
    function redeemCollateralForStableCoin() external {}

    /**
     * function to redeemSomeCallateral to reduce collateral sizing for DSC position
     */
    function redeemCollateral() external {}

    /**
     * function to burn stablecoin
     */

    function burn() external {}

    /**
     * function to liquidate users position to rebalance the protocol
     */

    function liquidate() external {}

    /**
     * function to view the health of a user's position and see the health of their position
     */
    function getHealthFactor() external view {}

    /**
     * function mintStableCoin, a function thats mints the stablecoin
     * @param amountDSCToMint the amount of stablecoin the user would like to mint
     * @notice they most have more collateral than dsc stablecoin
     */
    function mintDSC(uint256 amountDSCToMint) external moreThanZero(amountDSCToMint) {
        dscMinted[msg.sender] += amountDSCToMint;
        //if they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert MintFailed();
        }
    }

    ///////////////////
    // Public Functions
    ///////////////////

    ///////////////////
    // Private Functions
    ///////////////////

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
}
