// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";

import {Strings} from "openzeppelin/utils/Strings.sol";

import {PRBMathSD59x18} from "prb-math/PRBMathSD59x18.sol";

import {Goop} from "./Goop.sol";
import {VRGDA} from "./utils/VRGDA.sol";
import {LogisticVRGDA} from "./utils/LogisticVRGDA.sol";
import {PostSwitchVRGDA} from "./utils/PostSwitchVRGDA.sol";

/// @notice Pages is an ERC721 that can hold drawn art.
contract Pages is ERC721("Pages", "PAGE"), LogisticVRGDA, PostSwitchVRGDA {
    using Strings for uint256;
    using PRBMathSD59x18 for int256;

    /// ----------------------------
    /// --------- State ------------
    /// ----------------------------

    /// @notice Id of last mint.
    uint256 internal currentId;

    /// @notice The number of pages minted from goop.
    uint256 internal numMintedFromGoop;

    /// @notice Base token URI.
    string internal constant BASE_URI = "";

    /// @notice Mapping from tokenId to isDrawn bool.
    mapping(uint256 => bool) public isDrawn;

    Goop internal goop;

    /// ----------------------------
    /// ---- Pricing Parameters ----
    /// ----------------------------

    /// @notice The id of the first page to be priced using the post switch VRGDA.
    /// @dev Computed by plugging the switch day into the uninverted pacing formula.
    /// @dev Represented as an 18 decimal fixed point number.
    int256 internal constant SWITCH_ID_WAD = 9830.311074899383736712e18;

    /// @notice Start of public mint.
    /// @dev Begins as type(uint256).max to pagePrice() underflow before minting starts.
    uint256 private mintStart = type(uint256).max;

    /// -----------------------
    /// ------ Authority ------
    /// -----------------------

    /// @notice User allowed to set the draw state on pages.
    address public immutable artist;

    /// @notice Authority to mint with 0 cost.
    address public immutable artGobblers;

    error Unauthorized();

    constructor(address _goop, address _artist)
        VRGDA(
            4.20e18, // Initial price.
            0.31e18 // Per period price decrease.
        )
        LogisticVRGDA(
            // Logistic scale. We multiply by 2x (as a wad)
            // to account for the subtracted initial value,
            // and add 1 to ensure all the tokens can be sold:
            (9999 + 1) * 2e18,
            0.023e18 // Time scale.
        )
        PostSwitchVRGDA(
            SWITCH_ID_WAD, // Switch id.
            207e18, // Switch day.
            10e18 // Per day.
        )
    {
        goop = Goop(_goop);
        artist = _artist;
        artGobblers = msg.sender;
    }

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /// @notice Set whether a page is drawn.
    function setIsDrawn(uint256 tokenId) public only(artist) {
        isDrawn[tokenId] = true;
    }

    /// @notice Mint a page by burning goop.
    function mint() public {
        goop.burnForPages(msg.sender, pagePrice());

        _mint(msg.sender, ++currentId);

        numMintedFromGoop++;
    }

    /// @notice Set mint start timestamp for regular minting.
    function setMintStart(uint256 _mintStart) public only(artGobblers) {
        mintStart = _mintStart;
    }

    /// @notice Mint by authority without paying mint cost.
    function mintByAuth(address addr) public only(artGobblers) {
        _mint(addr, ++currentId);
    }

    /// @notice Calculate the mint cost of a page.
    /// @dev If the number of sales is below a pre-defined threshold, we use the
    /// VRGDA pricing algorithm, otherwise we use the post-switch pricing formula.
    /// @dev Reverts due to underflow if minting hasn't started yet. Done to save gas.
    function pagePrice() public view returns (uint256) {
        // We need checked math here to cause overflow
        // before minting has begun, preventing mints.
        uint256 timeSinceStart = block.timestamp - mintStart;

        return getPrice(timeSinceStart, numMintedFromGoop);
    }

    function getTargetSaleDay(int256 idWad) internal view override(LogisticVRGDA, PostSwitchVRGDA) returns (int256) {
        return idWad < SWITCH_ID_WAD ? LogisticVRGDA.getTargetSaleDay(idWad) : PostSwitchVRGDA.getTargetSaleDay(idWad);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (tokenId > currentId) return "";

        return string(abi.encodePacked(BASE_URI, tokenId.toString()));
    }
}
