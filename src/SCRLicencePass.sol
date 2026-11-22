// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice ERC-5192 minimal soulbound interface.
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}

/// @title SCR Licence Pass
/// @notice One non-transferable (ERC-5192 locked) ERC-721 pass per licensed domain for the
///         Strategic Crypto Reserve AI Build Configurator. Each pass records tier, a hash of the
///         licensed domain, term expiry and a revocation flag, so anyone can verify a licence.
/// @dev    domainHash = keccak256(bytes(lowercase hostname without "www.")), computed off-chain.
///         Card payments are minted by MINTER_ROLE. Optional USDC payments are pulled straight
///         from the payer to the treasury; the contract never holds funds.
contract SCRLicencePass is ERC721, AccessControl, ReentrancyGuard, IERC5192 {
    using SafeERC20 for IERC20;
    using Strings for uint256;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint8 public constant TIER_STANDARD = 1;
    uint8 public constant TIER_PRO = 2;
    uint8 public constant TIER_ENTERPRISE = 3;
    uint64 public constant TERM = 365 days;

    struct Licence {
        uint8 tier;
        bool revoked;
        uint64 expiry;
        bytes32 domainHash;
    }

    IERC20 public immutable usdc;
    address public treasury;
    uint256 public nextId = 1;

    mapping(uint256 tokenId => Licence) private _licences;
    mapping(bytes32 domainHash => uint256 tokenId) public tokenOfDomain;
    /// @notice USDC price (6 decimals) per tier for one TERM. 0 = not sold for USDC.
    mapping(uint8 tier => uint256 price) public usdcPrice;

    event LicenceMinted(uint256 indexed tokenId, address indexed to, bytes32 indexed domainHash, uint8 tier, uint64 expiry);
    event LicenceUpdated(uint256 indexed tokenId, uint8 tier, uint64 expiry);
    event LicenceRevoked(uint256 indexed tokenId, bool revoked);
    event PaidInUSDC(uint256 indexed tokenId, address indexed payer, uint256 amount);
    event PriceSet(uint8 indexed tier, uint256 price);
    event TreasurySet(address indexed treasury);

    error BadTier();
    error ZeroAddress();
    error ZeroDomain();
    error DomainTaken();
    error NoSuchToken();
    error Soulbound();
    error NotForSale();
    error ExpiryInPast();

    constructor(address admin, address minter, address treasury_, IERC20 usdc_)
        ERC721("SCR AI Build Configurator Licence", "SCRLIC")
    {
        if (admin == address(0) || minter == address(0) || treasury_ == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(MINTER_ROLE, minter);
        treasury = treasury_;
        usdc = usdc_;
        emit TreasurySet(treasury_);
    }

    // ------------------------------------------------------------------ minting (card / admin)

    /// @notice Mint a new licence pass for a domain (after card payment or migration).
    function mint(address to, bytes32 domainHash, uint8 tier, uint64 expiry)
        external
        onlyRole(MINTER_ROLE)
        returns (uint256 tokenId)
    {
        if (expiry <= block.timestamp) revert ExpiryInPast();
        tokenId = _mintLicence(to, domainHash, tier, expiry);
    }

    /// @notice Renew or change tier on an existing pass.
    function update(uint256 tokenId, uint8 tier, uint64 expiry) external onlyRole(MINTER_ROLE) {
        _requireOwned(tokenId);
        if (tier < TIER_STANDARD || tier > TIER_ENTERPRISE) revert BadTier();
        Licence storage l = _licences[tokenId];
        l.tier = tier;
        l.expiry = expiry;
        emit LicenceUpdated(tokenId, tier, expiry);
    }

    /// @notice Revoke (or un-revoke) a pass, e.g. after a refund or a terms breach.
    function setRevoked(uint256 tokenId, bool revoked) external onlyRole(MINTER_ROLE) {
        _requireOwned(tokenId);
        _licences[tokenId].revoked = revoked;
        emit LicenceRevoked(tokenId, revoked);
    }

    /// @notice Admin move of a locked pass, e.g. from the custodial holder to the licensee's own wallet.
    function adminTransfer(uint256 tokenId, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert ZeroAddress();
        _requireOwned(tokenId);
        _update(to, tokenId, address(0)); // emits Transfer

    }

    /// @notice Burn a pass and free its domain.
    function burn(uint256 tokenId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 d = _licences[tokenId].domainHash;
        _burn(tokenId); // reverts if nonexistent
        delete tokenOfDomain[d];
        delete _licences[tokenId];
    }

    // ------------------------------------------------------------------ optional USDC payment path

    /// @notice Buy (or renew) a licence for one TERM in USDC. USDC goes straight to the treasury.
    /// @param domainHash keccak256 of the licensed hostname
    /// @param tier       1 Standard, 2 Pro (Enterprise is quoted, so price 0 = not for sale)
    /// @param to         wallet that receives a NEW pass (ignored on renewal)
    function buyWithUSDC(bytes32 domainHash, uint8 tier, address to)
        external
        nonReentrant
        returns (uint256 tokenId)
    {
        uint256 price = usdcPrice[tier];
        if (price == 0) revert NotForSale();
        tokenId = tokenOfDomain[domainHash];
        // effects before the external call
        if (tokenId == 0) {
            tokenId = _mintLicence(to, domainHash, tier, uint64(block.timestamp) + TERM);
        } else {
            Licence storage l = _licences[tokenId];
            uint64 base = l.expiry > block.timestamp ? l.expiry : uint64(block.timestamp);
            l.tier = tier;
            l.expiry = base + TERM;
            emit LicenceUpdated(tokenId, tier, l.expiry);
        }
        emit PaidInUSDC(tokenId, msg.sender, price);
        usdc.safeTransferFrom(msg.sender, treasury, price);
    }

    function setUsdcPrice(uint8 tier, uint256 price) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (tier < TIER_STANDARD || tier > TIER_ENTERPRISE) revert BadTier();
        usdcPrice[tier] = price;
        emit PriceSet(tier, price);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasurySet(treasury_);
    }

    // ------------------------------------------------------------------ views

    function licence(uint256 tokenId) external view returns (Licence memory) {
        _requireOwned(tokenId);
        return _licences[tokenId];
    }

    /// @notice What the widget calls: is this domain licensed right now, and at what tier?
    function check(bytes32 domainHash) external view returns (bool valid, uint8 tier, uint64 expiry, uint256 tokenId) {
        tokenId = tokenOfDomain[domainHash];
        if (tokenId == 0) return (false, 0, 0, 0);
        Licence memory l = _licences[tokenId];
        valid = !l.revoked && l.expiry > block.timestamp;
        return (valid, l.tier, l.expiry, tokenId);
    }

    /// @inheritdoc IERC5192
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        Licence memory l = _licences[tokenId];
        string memory tierName = l.tier == TIER_STANDARD ? "Standard" : l.tier == TIER_PRO ? "Pro" : "Enterprise";
        string memory status = l.revoked ? "Revoked" : (l.expiry > block.timestamp ? "Active" : "Expired");
        bytes memory head = abi.encodePacked(
            '{"name":"SCR Configurator Licence #', tokenId.toString(),
            '","description":"Non-transferable licence pass for the Strategic Crypto Reserve AI Build Configurator. Verify at strategiccryptoreserve.ca.",',
            '"external_url":"https://strategiccryptoreserve.ca/ai-build-configurator.html",'
        );
        bytes memory attrs = abi.encodePacked(
            '"attributes":[{"trait_type":"Tier","value":"', tierName,
            '"},{"trait_type":"Status","value":"', status,
            '"},{"display_type":"date","trait_type":"Expiry","value":', uint256(l.expiry).toString(),
            '},{"trait_type":"Domain hash","value":"', uint256(l.domainHash).toHexString(32), '"}]}'
        );
        bytes memory json = bytes.concat(head, attrs);
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return interfaceId == type(IERC5192).interfaceId || super.supportsInterface(interfaceId);
    }

    // ------------------------------------------------------------------ internals

    function _mintLicence(address to, bytes32 domainHash, uint8 tier, uint64 expiry) internal returns (uint256 tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (domainHash == bytes32(0)) revert ZeroDomain();
        if (tier < TIER_STANDARD || tier > TIER_ENTERPRISE) revert BadTier();
        if (tokenOfDomain[domainHash] != 0) revert DomainTaken();
        tokenId = nextId++;
        _licences[tokenId] = Licence({tier: tier, revoked: false, expiry: expiry, domainHash: domainHash});
        tokenOfDomain[domainHash] = tokenId;
        _mint(to, tokenId); // _mint, not _safeMint: no receiver callback (custodial/EOA holders)
        emit Locked(tokenId);
        emit LicenceMinted(tokenId, to, domainHash, tier, expiry);
    }

    /// @dev Soulbound: block every owner-initiated transfer and approval path. Mint, burn and
    ///      adminTransfer call _update with auth == address(0) and are allowed.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0) && auth != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal override {
        if (to != address(0)) revert Soulbound();
        super._approve(to, tokenId, auth, emitEvent);
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal override {
        if (approved) revert Soulbound();
        super._setApprovalForAll(owner, operator, approved);
    }
}
