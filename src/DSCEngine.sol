// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./StableCoin.sol";

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
    /**********
     * Errors *
     **********/
    error NeedsMoreThanZero();
    error TokenAddressesAndPriceAddressesMustBeSameLength();

    /**********************
     * State Variables *
     **********************/
    mapping(address token => address priceFeed) private priceFeeds; //mapping fo token address to price feed address

    StableCoin private immutable dsc;

    /*************
     * Modifiers *
     *************/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {}

    /*************
     * Functions *
     *************/
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert TokenAddressesAndPriceAddressesMustBeSameLength();
        }

        //set mapping of price feeds
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        dsc = StableCoin(dscAddress);
    }

    /**********************
     * External Functions *
     **********************/

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
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) external moreThanZero(amountCollateral) {}

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
     */
    function mintDSC() external {}
}
