// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SCRLicencePass, IERC5192} from "../src/SCRLicencePass.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USDC", "USDC") {}
    function decimals() public pure override returns (uint8) { return 6; }
    function mint(address to, uint256 amt) external { _mint(to, amt); }
}

contract SCRLicencePassTest is Test {
    SCRLicencePass pass;
    MockUSDC usdc;
    address admin = makeAddr("admin");
    address minter = makeAddr("minter");
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    bytes32 constant D1 = keccak256("example.com");
    bytes32 constant D2 = keccak256("client.example.org");

    event Locked(uint256 tokenId);

    function setUp() public {
        usdc = new MockUSDC();
        pass = new SCRLicencePass(admin, minter, treasury, IERC20(address(usdc)));
    }

    function _mint1() internal returns (uint256) {
        vm.prank(minter);
        return pass.mint(alice, D1, 1, uint64(block.timestamp + 365 days));
    }

    // ---------------------------------------------------------------- constructor
    function test_constructor() public view {
        assertTrue(pass.hasRole(pass.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pass.hasRole(pass.MINTER_ROLE(), minter));
        assertEq(pass.treasury(), treasury);
        assertEq(address(pass.usdc()), address(usdc));
        assertEq(pass.name(), "SCR AI Build Configurator Licence");
        assertEq(pass.symbol(), "SCRLIC");
        assertEq(pass.nextId(), 1);
    }

    function test_constructor_zeroAddress() public {
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        new SCRLicencePass(address(0), minter, treasury, IERC20(address(usdc)));
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        new SCRLicencePass(admin, address(0), treasury, IERC20(address(usdc)));
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        new SCRLicencePass(admin, minter, address(0), IERC20(address(usdc)));
    }

    // ---------------------------------------------------------------- mint
    function test_mint() public {
        vm.expectEmit(address(pass));
        emit Locked(1);
        uint256 id = _mint1();
        assertEq(id, 1);
        assertEq(pass.ownerOf(1), alice);
        assertEq(pass.tokenOfDomain(D1), 1);
        SCRLicencePass.Licence memory l = pass.licence(1);
        assertEq(l.tier, 1);
        assertEq(l.domainHash, D1);
        assertFalse(l.revoked);
        assertEq(pass.nextId(), 2);
    }

    function test_mint_onlyMinter() public {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pass.MINTER_ROLE()));
        vm.prank(alice);
        pass.mint(alice, D1, 1, uint64(block.timestamp + 1));
    }

    function test_mint_reverts() public {
        uint64 exp = uint64(block.timestamp + 1 days);
        vm.startPrank(minter);
        vm.expectRevert(SCRLicencePass.ExpiryInPast.selector);
        pass.mint(alice, D1, 1, uint64(block.timestamp));
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        pass.mint(address(0), D1, 1, exp);
        vm.expectRevert(SCRLicencePass.ZeroDomain.selector);
        pass.mint(alice, bytes32(0), 1, exp);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.mint(alice, D1, 0, exp);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.mint(alice, D1, 4, exp);
        pass.mint(alice, D1, 3, exp);
        vm.expectRevert(SCRLicencePass.DomainTaken.selector);
        pass.mint(bob, D1, 2, exp);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- update / revoke
    function test_update() public {
        _mint1();
        vm.prank(minter);
        pass.update(1, 2, uint64(block.timestamp + 730 days));
        SCRLicencePass.Licence memory l = pass.licence(1);
        assertEq(l.tier, 2);
        assertEq(l.expiry, uint64(block.timestamp + 730 days));
    }

    function test_update_reverts() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 9));
        pass.update(9, 1, 1);
        _mint1();
        vm.prank(minter);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.update(1, 0, 1);
        vm.prank(minter);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.update(1, 4, 1);
        vm.prank(alice);
        vm.expectRevert();
        pass.update(1, 1, 1);
    }

    function test_revoke_and_restore() public {
        _mint1();
        (bool valid,,,) = pass.check(D1);
        assertTrue(valid);
        vm.prank(minter);
        pass.setRevoked(1, true);
        (valid,,,) = pass.check(D1);
        assertFalse(valid);
        assertTrue(pass.licence(1).revoked);
        vm.prank(minter);
        pass.setRevoked(1, false);
        (valid,,,) = pass.check(D1);
        assertTrue(valid);
    }

    function test_revoke_nonexistent() public {
        vm.prank(minter);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 5));
        pass.setRevoked(5, true);
    }

    // ---------------------------------------------------------------- check / expiry
    function test_check() public {
        (bool valid, uint8 tier, uint64 exp, uint256 id) = pass.check(D1);
        assertFalse(valid);
        assertEq(tier, 0); assertEq(exp, 0); assertEq(id, 0);
        _mint1();
        (valid, tier, exp, id) = pass.check(D1);
        assertTrue(valid);
        assertEq(tier, 1); assertEq(id, 1);
        vm.warp(exp);          // expiry is exclusive
        (valid,,,) = pass.check(D1);
        assertFalse(valid);
    }

    // ---------------------------------------------------------------- soulbound
    function test_locked() public {
        _mint1();
        assertTrue(pass.locked(1));
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 2));
        pass.locked(2);
    }

    function test_transfer_blocked() public {
        _mint1();
        vm.startPrank(alice);
        vm.expectRevert(SCRLicencePass.Soulbound.selector);
        pass.transferFrom(alice, bob, 1);
        vm.expectRevert(SCRLicencePass.Soulbound.selector);
        pass.safeTransferFrom(alice, bob, 1);
        vm.expectRevert(SCRLicencePass.Soulbound.selector);
        pass.safeTransferFrom(alice, bob, 1, "");
        vm.expectRevert(SCRLicencePass.Soulbound.selector);
        pass.approve(bob, 1);
        vm.expectRevert(SCRLicencePass.Soulbound.selector);
        pass.setApprovalForAll(bob, true);
        pass.setApprovalForAll(bob, false); // revoking is harmless and allowed
        vm.stopPrank();
        assertEq(pass.ownerOf(1), alice);
    }

    function test_adminTransfer() public {
        _mint1();
        vm.prank(admin);
        pass.adminTransfer(1, bob);
        assertEq(pass.ownerOf(1), bob);
        assertEq(pass.balanceOf(alice), 0);
    }

    function test_adminTransfer_reverts() public {
        _mint1();
        vm.prank(admin);
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        pass.adminTransfer(1, address(0));
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 7));
        pass.adminTransfer(7, bob);
        vm.prank(minter);
        vm.expectRevert();
        pass.adminTransfer(1, bob);
    }

    function test_burn_frees_domain() public {
        _mint1();
        vm.prank(admin);
        pass.burn(1);
        assertEq(pass.tokenOfDomain(D1), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        pass.ownerOf(1);
        vm.prank(minter);
        uint256 id = pass.mint(bob, D1, 2, uint64(block.timestamp + 1 days));
        assertEq(id, 2);
    }

    function test_burn_reverts() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 3));
        pass.burn(3);
        _mint1();
        vm.prank(minter);
        vm.expectRevert();
        pass.burn(1);
    }

    // ---------------------------------------------------------------- USDC path
    function _price() internal {
        vm.startPrank(admin);
        pass.setUsdcPrice(1, 2_900e6);
        pass.setUsdcPrice(2, 7_250e6);
        vm.stopPrank();
    }

    function test_buy_notForSale() public {
        vm.expectRevert(SCRLicencePass.NotForSale.selector);
        pass.buyWithUSDC(D1, 1, alice);
        vm.expectRevert(SCRLicencePass.NotForSale.selector);
        pass.buyWithUSDC(D1, 3, alice);
    }

    function test_buy_new() public {
        _price();
        usdc.mint(bob, 2_900e6);
        vm.startPrank(bob);
        usdc.approve(address(pass), 2_900e6);
        uint256 id = pass.buyWithUSDC(D1, 1, alice);
        vm.stopPrank();
        assertEq(pass.ownerOf(id), alice);
        assertEq(usdc.balanceOf(treasury), 2_900e6);
        assertEq(usdc.balanceOf(address(pass)), 0);
        (bool valid, uint8 tier, uint64 exp,) = pass.check(D1);
        assertTrue(valid);
        assertEq(tier, 1);
        assertEq(exp, uint64(block.timestamp) + pass.TERM());
    }

    function test_buy_renew_active_extends_from_expiry() public {
        _price();
        _mint1();
        uint64 oldExp = pass.licence(1).expiry;
        usdc.mint(alice, 7_250e6);
        vm.startPrank(alice);
        usdc.approve(address(pass), 7_250e6);
        uint256 id = pass.buyWithUSDC(D1, 2, bob);
        vm.stopPrank();
        assertEq(id, 1);
        assertEq(pass.ownerOf(1), alice); // renewal never moves the pass
        assertEq(pass.licence(1).tier, 2);
        assertEq(pass.licence(1).expiry, oldExp + pass.TERM());
    }

    function test_buy_renew_expired_extends_from_now() public {
        _price();
        _mint1();
        vm.warp(block.timestamp + 400 days);
        usdc.mint(alice, 2_900e6);
        vm.startPrank(alice);
        usdc.approve(address(pass), 2_900e6);
        pass.buyWithUSDC(D1, 1, alice);
        vm.stopPrank();
        assertEq(pass.licence(1).expiry, uint64(block.timestamp) + pass.TERM());
    }

    function test_buy_insufficientAllowance() public {
        _price();
        usdc.mint(bob, 2_900e6);
        vm.prank(bob);
        vm.expectRevert();
        pass.buyWithUSDC(D1, 1, alice);
        assertEq(pass.tokenOfDomain(D1), 0); // whole tx reverted, nothing minted
    }

    function test_setUsdcPrice() public {
        vm.prank(admin);
        pass.setUsdcPrice(3, 1);
        assertEq(pass.usdcPrice(3), 1);
        vm.startPrank(admin);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.setUsdcPrice(0, 1);
        vm.expectRevert(SCRLicencePass.BadTier.selector);
        pass.setUsdcPrice(4, 1);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectRevert();
        pass.setUsdcPrice(1, 1);
    }

    function test_setTreasury() public {
        vm.prank(admin);
        pass.setTreasury(bob);
        assertEq(pass.treasury(), bob);
        vm.prank(admin);
        vm.expectRevert(SCRLicencePass.ZeroAddress.selector);
        pass.setTreasury(address(0));
        vm.prank(alice);
        vm.expectRevert();
        pass.setTreasury(alice);
    }

    // ---------------------------------------------------------------- metadata / interfaces
    function test_tokenURI() public {
        _mint1();
        string memory uri = pass.tokenURI(1);
        assertEq(_prefix(uri, 29), "data:application/json;base64,");
        vm.prank(minter);
        pass.mint(bob, D2, 2, uint64(block.timestamp + 10));
        vm.prank(minter);
        pass.update(2, 3, uint64(block.timestamp + 10));
        assertTrue(bytes(pass.tokenURI(2)).length > 29); // Enterprise branch
        vm.prank(minter);
        pass.setRevoked(2, true);
        assertTrue(bytes(pass.tokenURI(2)).length > 29); // Revoked branch
        vm.warp(block.timestamp + 366 days);
        assertTrue(bytes(pass.tokenURI(1)).length > 29); // Expired branch
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 99));
        pass.tokenURI(99);
    }

    function test_tokenURI_pro() public {
        vm.prank(minter);
        pass.mint(bob, D2, 2, uint64(block.timestamp + 10));
        assertTrue(bytes(pass.tokenURI(1)).length > 29);
    }

    function test_licence_nonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        pass.licence(1);
    }

    function test_supportsInterface() public view {
        assertTrue(pass.supportsInterface(0xb45a3c0e)); // ERC-5192
        assertTrue(pass.supportsInterface(type(IERC5192).interfaceId));
        assertTrue(pass.supportsInterface(type(IERC721).interfaceId));
        assertTrue(pass.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(pass.supportsInterface(0x01ffc9a7)); // ERC-165
        assertFalse(pass.supportsInterface(0xffffffff));
    }

    // ---------------------------------------------------------------- fuzz
    function testFuzz_onePassPerDomain(bytes32 d, uint8 tier) public {
        vm.assume(d != bytes32(0));
        tier = uint8(bound(tier, 1, 3));
        vm.startPrank(minter);
        pass.mint(alice, d, tier, uint64(block.timestamp + 1));
        vm.expectRevert(SCRLicencePass.DomainTaken.selector);
        pass.mint(bob, d, tier, uint64(block.timestamp + 1));
        vm.stopPrank();
    }

    function _prefix(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; i++) out[i] = b[i];
        return string(out);
    }
}
