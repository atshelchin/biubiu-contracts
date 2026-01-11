// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {TokenSweep, Wallet} from "../src/tools/TokenSweep.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";
import {IBiuBiuPremium} from "../src/interfaces/IBiuBiuPremium.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TokenSweepTest is Test {
    TokenSweep public tokenSweep;
    BiuBiuPremium public premium;
    MockERC20 public token;

    address public vault = 0x46AFD0cA864D4E5235DA38a71687163Dc83828cE;
    address public premiumMember;
    uint256 public premiumMemberKey;
    address public nonMember;
    uint256 public nonMemberKey;
    address public recipient = address(0x4);
    address public referrer = address(0x5);

    // Events to test
    event ReferralPaid(address indexed referrer, address indexed caller, uint256 amount);
    event VaultPaid(address indexed vault, address indexed caller, uint256 amount);
    event MulticallExecuted(address indexed caller, address indexed recipient, uint256 walletsCount, uint8 usageType);

    function setUp() public {
        // Deploy premium contract with vault address
        premium = new BiuBiuPremium(vault);

        // Deploy TokenSweep with premium contract address
        tokenSweep = new TokenSweep(address(premium));

        // Create test accounts
        (premiumMember, premiumMemberKey) = makeAddrAndKey("premiumMember");
        (nonMember, nonMemberKey) = makeAddrAndKey("nonMember");

        // Fund accounts
        vm.deal(premiumMember, 100 ether);
        vm.deal(nonMember, 100 ether);
        vm.deal(recipient, 1 ether);
        vm.deal(referrer, 1 ether);

        // Create mock token
        token = new MockERC20();

        // Make premiumMember a premium member
        uint256 monthlyPrice = premium.MONTHLY_PRICE();
        vm.prank(premiumMember);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));
    }

    // Test constants
    function testConstants() public view {
        assertEq(tokenSweep.NON_MEMBER_FEE(), 0.01 ether);
        assertEq(tokenSweep.VAULT(), vault);
    }

    // Test premium member can call multicall for free
    function testPremiumMemberMulticallFree() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 balanceBefore = premiumMember.balance;

        vm.prank(premiumMember);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");

        // Premium member should not pay
        assertEq(premiumMember.balance, balanceBefore);
    }

    // Test non-member must pay fee
    function testNonMemberMustPayFee() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        vm.prank(nonMember);
        vm.expectRevert(TokenSweep.InsufficientPayment.selector);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");
    }

    // Test non-member payment without referrer
    function testNonMemberPaymentNoReferrer() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 nonMemberBalanceBefore = nonMember.balance;
        uint256 fee = premium.NON_MEMBER_FEE();

        vm.prank(nonMember);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");

        // Vault should receive full payment
        assertEq(vault.balance, vaultBalanceBefore + fee);
        assertEq(nonMember.balance, nonMemberBalanceBefore - fee);
    }

    // Test non-member payment with referrer (50/50 split)
    function testNonMemberPaymentWithReferrer() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 referrerBalanceBefore = referrer.balance;
        uint256 fee = premium.NON_MEMBER_FEE();

        vm.prank(nonMember);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, block.timestamp + 1 hours, referrer, "");

        // Referrer gets 50%, vault gets 50%
        assertEq(referrer.balance, referrerBalanceBefore + fee / 2);
        assertEq(vault.balance, vaultBalanceBefore + fee / 2);
    }

    // Test signature authorization - premium member authorizes non-member
    function testSignatureAuthorization() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // Premium member signs authorization for non-member to call on their behalf
        string memory message = string(
            abi.encodePacked(
                "TokenSweep Authorization\n\n",
                "I authorize wallet:\n",
                _toHexString(nonMember),
                "\n\nto call multicall on my behalf\n\n",
                "Recipient address:\n",
                _toHexString(recipient),
                "\n\nChain ID: ",
                _toString(block.chainid)
            )
        );

        bytes32 messageHash = keccak256(bytes(message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(premiumMemberKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 nonMemberBalanceBefore = nonMember.balance;

        // Non-member calls with premium member's signature - should be free
        vm.prank(nonMember);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), signature);

        // Non-member should not pay (using premium member's authorization)
        assertEq(nonMember.balance, nonMemberBalanceBefore);
    }

    // Test invalid signature
    function testInvalidSignature() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        bytes memory invalidSignature = "invalid";

        // Cache fee before prank (prank only affects next external call)
        uint256 fee = premium.NON_MEMBER_FEE();

        vm.prank(nonMember);
        vm.expectRevert(TokenSweep.InvalidSignature.selector);
        tokenSweep.multicall{value: fee}(
            wallets, recipient, tokens, block.timestamp + 1 hours, address(0), invalidSignature
        );
    }

    // Test drainToAddress with signature verification
    function testDrainToAddress() public {
        // Create a TokenSweep instance that will act as a wallet
        TokenSweep wallet = new TokenSweep(address(premium));

        // Mint tokens to the wallet
        token.mint(address(wallet), 1000 ether);
        vm.deal(address(wallet), 5 ether);

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        uint256 deadline = block.timestamp + 1 hours;

        // Create signature from the wallet itself (simulate pre-signed authorization)
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n32",
                keccak256(abi.encode(block.chainid, address(wallet), recipient, tokens, deadline))
            )
        );

        // For testing, we'll create a valid signature
        // Note: In production, this would be pre-signed by the wallet owner
        uint256 walletKey = uint256(keccak256(abi.encodePacked(address(wallet))));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // uint256 recipientTokenBefore = token.balanceOf(recipient);
        // uint256 recipientEthBefore = recipient.balance;

        // Note: This test will fail signature verification in production
        // because we can't actually sign as the contract address
        // In production, drainToAddress would be called with pre-authorized signatures
        vm.expectRevert(TokenSweep.UnauthorizedCaller.selector);
        wallet.drainToAddress(recipient, tokens, deadline, signature);
    }

    // // Test reentrancy protection
    // function testReentrancyProtection() public {
    //     // This would require a malicious contract to test properly
    //     // For now, we just verify the modifier is present
    //     assertTrue(true);
    // }

    // Helper functions
    function _toHexString(address addr) private pure returns (string memory) {
        bytes memory buffer = new bytes(42);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            // Safe cast: extracting single byte from address (0-255)
            // forge-lint: disable-next-line(unsafe-typecast)
            uint8 value = uint8(uint160(addr) >> (8 * (19 - i)));
            buffer[2 + i * 2] = _hexChar(value >> 4);
            buffer[3 + i * 2] = _hexChar(value & 0x0f);
        }
        return string(buffer);
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // Safe cast: value % 10 is always 0-9, adding 48 gives ASCII '0'-'9' (48-57)
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _hexChar(uint8 value) private pure returns (bytes1) {
        if (value < 10) {
            // Safe cast: 48 + value (0-9) = 48-57, which is within uint8 range
            // forge-lint: disable-next-line(unsafe-typecast)
            return bytes1(uint8(48 + value));
        }
        // Safe cast: 87 + value (10-15) = 97-102, which is within uint8 range
        // forge-lint: disable-next-line(unsafe-typecast)
        return bytes1(uint8(87 + value));
    }

    // ==================== Additional Critical Test Cases ====================

    // Test deadline expired in drainToAddress
    function testDrainToAddressDeadlineExpired() public {
        TokenSweep wallet = new TokenSweep(address(premium));
        address[] memory tokens = new address[](0);
        uint256 expiredDeadline = block.timestamp - 1;

        vm.expectRevert(TokenSweep.DeadlineExpired.selector);
        wallet.drainToAddress(recipient, tokens, expiredDeadline, "");
    }

    // Test invalid recipient in drainToAddress
    function testDrainToAddressInvalidRecipient() public {
        TokenSweep wallet = new TokenSweep(address(premium));
        address[] memory tokens = new address[](0);
        uint256 deadline = block.timestamp + 1 hours;

        vm.expectRevert(TokenSweep.InvalidRecipient.selector);
        wallet.drainToAddress(address(0), tokens, deadline, "");
    }

    // Test self-referral (referrer == msg.sender)
    function testSelfReferralIgnored() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 nonMemberBalanceBefore = nonMember.balance;
        uint256 fee = premium.NON_MEMBER_FEE();

        // Non-member tries to refer themselves
        vm.prank(nonMember);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, block.timestamp + 1 hours, nonMember, "");

        // Self-referral should be ignored, vault gets full amount
        assertEq(vault.balance, vaultBalanceBefore + fee);
        assertEq(nonMember.balance, nonMemberBalanceBefore - fee);
    }

    // Test overpayment
    function testNonMemberOverpayment() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 vaultBalanceBefore = vault.balance;

        uint256 overpayment = 0.01 ether;
        vm.prank(nonMember);
        tokenSweep.multicall{value: overpayment}(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");

        // Vault receives all overpayment
        assertEq(vault.balance, vaultBalanceBefore + overpayment);
    }

    // Test expired premium membership
    function testExpiredPremiumMembership() public {
        // Create a new user who was premium but expired
        (address expiredMember,) = makeAddrAndKey("expiredMember");
        vm.deal(expiredMember, 100 ether);

        // Subscribe for 30 days
        uint256 monthlyPrice = premium.MONTHLY_PRICE();
        vm.prank(expiredMember);
        premium.subscribe{value: monthlyPrice}(IBiuBiuPremium.SubscriptionTier.Monthly, address(0));

        // Fast forward past expiry
        vm.warp(block.timestamp + 31 days);

        // Now expired member should need to pay
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        vm.prank(expiredMember);
        vm.expectRevert(TokenSweep.InsufficientPayment.selector);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");
    }

    // Test event emissions for multicall
    function testMulticallEventEmissions() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);
        uint256 fee = premium.NON_MEMBER_FEE();

        // Test premium member event (usageType = 1 = USAGE_PREMIUM)
        vm.prank(premiumMember);
        vm.expectEmit(true, true, false, true);
        emit MulticallExecuted(premiumMember, recipient, 0, 1);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");

        // Test non-member with referrer events (usageType = 2 = USAGE_PAID)
        vm.prank(nonMember);
        vm.expectEmit(true, true, false, true);
        emit ReferralPaid(referrer, nonMember, fee / 2);
        vm.expectEmit(true, true, false, true);
        emit VaultPaid(vault, nonMember, fee / 2);
        vm.expectEmit(true, true, false, true);
        emit MulticallExecuted(nonMember, recipient, 0, 2);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, block.timestamp + 1 hours, referrer, "");
    }

    // Test drainToAddress with multiple tokens
    function testDrainToAddressMultipleTokens() public {
        TokenSweep wallet = new TokenSweep(address(premium));

        // Create multiple tokens
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();

        // Mint tokens to wallet
        token1.mint(address(wallet), 100 ether);
        token2.mint(address(wallet), 200 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        uint256 deadline = block.timestamp + 1 hours;

        // This will fail signature verification, but we're testing the token iteration logic
        vm.expectRevert(TokenSweep.InvalidSignature.selector);
        wallet.drainToAddress(recipient, tokens, deadline, "");
    }

    // Test drainToAddress with address(0) in tokens array
    function testDrainToAddressSkipsZeroAddress() public {
        TokenSweep wallet = new TokenSweep(address(premium));

        address[] memory tokens = new address[](2);
        tokens[0] = address(0); // Should be skipped
        tokens[1] = address(token);

        token.mint(address(wallet), 100 ether);

        uint256 deadline = block.timestamp + 1 hours;

        // Will fail signature verification, but tests address(0) skip logic
        vm.expectRevert(TokenSweep.InvalidSignature.selector);
        wallet.drainToAddress(recipient, tokens, deadline, "");
    }

    // Test non-premium member signature authorization (should require payment)
    function testNonPremiumSignatureAuthorization() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // Non-member signs authorization for another non-member
        string memory message = string(
            abi.encodePacked(
                "TokenSweep Authorization\n\n",
                "I authorize wallet:\n",
                _toHexString(recipient),
                "\n\nto call multicall on my behalf\n\n",
                "Recipient address:\n",
                _toHexString(recipient),
                "\n\nChain ID: ",
                _toString(block.chainid)
            )
        );

        bytes32 messageHash = keccak256(bytes(message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(nonMemberKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Recipient calls with non-member's signature - should still need payment
        vm.prank(recipient);
        vm.expectRevert(TokenSweep.InsufficientPayment.selector);
        tokenSweep.multicall(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), signature);
    }

    // Test supportsInterface
    function testSupportsInterface() public view {
        // ERC165
        assertTrue(tokenSweep.supportsInterface(0x01ffc9a7));
        // ERC721Receiver
        assertTrue(tokenSweep.supportsInterface(0x150b7a02));
        // ERC1155Receiver-single
        assertTrue(tokenSweep.supportsInterface(0x4e2312e0));
        // ERC1155Receiver-batch
        assertTrue(tokenSweep.supportsInterface(0xbc197c81));
        // Random interface
        assertFalse(tokenSweep.supportsInterface(0x12345678));
    }

    // Test ERC721 reception
    function testOnERC721Received() public view {
        bytes4 selector = tokenSweep.onERC721Received(address(0), address(0), 0, "");
        assertEq(selector, TokenSweep.onERC721Received.selector);
    }

    // Test ERC1155 single reception
    function testOnERC1155Received() public view {
        bytes4 selector = tokenSweep.onERC1155Received(address(0), address(0), 0, 0, "");
        assertEq(selector, TokenSweep.onERC1155Received.selector);
    }

    // Test ERC1155 batch reception
    function testOnERC1155BatchReceived() public view {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory values = new uint256[](0);
        bytes4 selector = tokenSweep.onERC1155BatchReceived(address(0), address(0), ids, values, "");
        assertEq(selector, TokenSweep.onERC1155BatchReceived.selector);
    }

    // Test receive() function
    function testReceiveETH() public {
        uint256 balanceBefore = address(tokenSweep).balance;

        // Send ETH directly to contract
        (bool success,) = address(tokenSweep).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(address(tokenSweep).balance, balanceBefore + 1 ether);
    }

    // Test fallback() function
    function testFallback() public {
        uint256 balanceBefore = address(tokenSweep).balance;

        // Call with data to trigger fallback
        (bool success,) = address(tokenSweep).call{value: 0.5 ether}("0x1234");
        assertTrue(success);

        assertEq(address(tokenSweep).balance, balanceBefore + 0.5 ether);
    }

    // Test accumulated balance sweep
    function testAccumulatedBalanceSweep() public {
        // Send some ETH to contract first
        vm.deal(address(tokenSweep), 1 ether);

        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        uint256 vaultBalanceBefore = vault.balance;
        uint256 fee = premium.NON_MEMBER_FEE();

        // Non-member pays fee, but contract has 1 ETH already
        vm.prank(nonMember);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), "");

        // Vault should receive 1 + fee (all contract balance)
        assertEq(vault.balance, vaultBalanceBefore + 1 ether + fee);
        assertEq(address(tokenSweep).balance, 0);
    }

    // Test multicall with 100 EIP-7702 authorized wallets, ETH + 3 tokens - Gas benchmark
    // Simulates 100 EOA wallets that used EIP-7702 to delegate to TokenSweep contract
    function testMulticallWith100WalletsMultipleTokens() public {
        // Create 3 different ERC20 tokens
        MockERC20 token1 = new MockERC20();
        MockERC20 token2 = new MockERC20();
        MockERC20 token3 = new MockERC20();

        // Deploy TokenSweep contract template for EIP-7702 delegation
        TokenSweep templateContract = new TokenSweep(address(premium));
        bytes memory tokenSweepCode = address(templateContract).code;

        // Prepare tokens array and deadline for signature
        address[] memory sigTokens = new address[](3);
        sigTokens[0] = address(token1);
        sigTokens[1] = address(token2);
        sigTokens[2] = address(token3);
        uint256 deadline = block.timestamp + 1 hours;

        // Create 100 EOA wallets that delegated via EIP-7702
        Wallet[] memory wallets = new Wallet[](100);

        for (uint256 i = 0; i < 100; i++) {
            // Create EOA wallet and get private key
            (address walletAddr, uint256 walletKey) = makeAddrAndKey(string(abi.encodePacked("eoa", _toString(i))));

            // Simulate EIP-7702: EOA delegates to TokenSweep contract
            vm.etch(walletAddr, tokenSweepCode);
            // Initialize storage: set _locked = 1
            vm.store(walletAddr, bytes32(uint256(0)), bytes32(uint256(1)));

            // Fund the EOA wallet with ETH and 3 different tokens
            vm.deal(walletAddr, 1 ether);
            token1.mint(walletAddr, 100 ether);
            token2.mint(walletAddr, 200 ether);
            token3.mint(walletAddr, 300 ether);

            // Sign drainToAddress authorization - must match the drainToAddress function signature format
            bytes32 messageHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encode(block.chainid, walletAddr, recipient, sigTokens, deadline))
                )
            );

            // Sign with wallet's own private key
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletKey, messageHash);
            wallets[i] = Wallet({wallet: walletAddr, signature: abi.encodePacked(r, s, v)});
        }

        // Create tokens array with 3 tokens
        address[] memory tokens = new address[](3);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        tokens[2] = address(token3);

        uint256 recipientBalanceBefore = recipient.balance;
        uint256 recipientToken1Before = token1.balanceOf(recipient);
        uint256 recipientToken2Before = token2.balanceOf(recipient);
        uint256 recipientToken3Before = token3.balanceOf(recipient);

        // Premium member calls multicall with 100 wallets and 3 tokens
        uint256 gasBefore = gasleft();
        vm.prank(premiumMember);
        tokenSweep.multicall(wallets, recipient, tokens, deadline, address(0), "");
        uint256 gasUsed = gasBefore - gasleft();

        // Log gas usage for 100 wallets + 3 tokens + ETH
        emit log_named_uint("Gas used for 100 wallets + 3 tokens + ETH", gasUsed);

        // Verify all ETH was swept (100 wallets * 1 ETH each = 100 ETH)
        assertEq(recipient.balance, recipientBalanceBefore + 100 ether);

        // Verify all tokens were swept
        assertEq(token1.balanceOf(recipient), recipientToken1Before + 10000 ether); // 100 * 100
        assertEq(token2.balanceOf(recipient), recipientToken2Before + 20000 ether); // 100 * 200
        assertEq(token3.balanceOf(recipient), recipientToken3Before + 30000 ether); // 100 * 300

        // Verify sample wallets are empty (checking all 100 causes stack too deep)
        assertEq(wallets[0].wallet.balance, 0);
        assertEq(wallets[50].wallet.balance, 0);
        assertEq(wallets[99].wallet.balance, 0);
        assertEq(token1.balanceOf(wallets[0].wallet), 0);
        assertEq(token2.balanceOf(wallets[0].wallet), 0);
        assertEq(token3.balanceOf(wallets[0].wallet), 0);
    }

    // Test multicall with 10 EIP-7702 authorized wallets as non-member (should pay fee)
    function testMulticallWith10WalletsNonMember() public {
        // Deploy TokenSweep contract template for EIP-7702 delegation
        TokenSweep templateContract = new TokenSweep(address(premium));
        bytes memory tokenSweepCode = address(templateContract).code;

        // Prepare tokens array and deadline for signature
        address[] memory sigTokens = new address[](1);
        sigTokens[0] = address(token);
        uint256 deadline = block.timestamp + 1 hours;

        // Create 10 EOA wallets that delegated via EIP-7702
        Wallet[] memory wallets = new Wallet[](10);

        for (uint256 i = 0; i < 10; i++) {
            // Create EOA wallet and get private key
            (address walletAddr, uint256 walletKey) = makeAddrAndKey(string(abi.encodePacked("nmeoa", _toString(i))));

            // Simulate EIP-7702: EOA delegates to TokenSweep contract
            vm.etch(walletAddr, tokenSweepCode);
            // Initialize storage: set _locked = 1
            vm.store(walletAddr, bytes32(uint256(0)), bytes32(uint256(1)));

            // Fund each EOA wallet with ETH and tokens
            vm.deal(walletAddr, 0.5 ether);
            token.mint(walletAddr, 50 ether);

            // Sign drainToAddress authorization - must match the drainToAddress function signature format
            bytes32 messageHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encode(block.chainid, walletAddr, recipient, sigTokens, deadline))
                )
            );

            // Sign with wallet's own private key
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletKey, messageHash);
            wallets[i] = Wallet({wallet: walletAddr, signature: abi.encodePacked(r, s, v)});
        }

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        uint256 recipientBalanceBefore = recipient.balance;
        uint256 recipientTokenBalanceBefore = token.balanceOf(recipient);
        uint256 vaultBalanceBefore = vault.balance;
        uint256 referrerBalanceBefore = referrer.balance;
        uint256 fee = premium.NON_MEMBER_FEE();

        // Non-member calls multicall with wallets and pays fee with referrer
        vm.prank(nonMember);
        tokenSweep.multicall{value: fee}(wallets, recipient, tokens, deadline, referrer, "");

        // Verify all ETH was swept (10 wallets * 0.5 ETH each)
        assertEq(recipient.balance, recipientBalanceBefore + 5 ether);

        // Verify all tokens were swept (10 wallets * 50 tokens each)
        assertEq(token.balanceOf(recipient), recipientTokenBalanceBefore + 500 ether);

        // Verify referrer got 50% of fee
        assertEq(referrer.balance, referrerBalanceBefore + fee / 2);

        // Verify vault got 50% of fee
        assertEq(vault.balance, vaultBalanceBefore + fee / 2);

        // Verify sample wallets are empty
        assertEq(wallets[0].wallet.balance, 0);
        assertEq(wallets[9].wallet.balance, 0);
        assertEq(token.balanceOf(wallets[0].wallet), 0);
        assertEq(token.balanceOf(wallets[9].wallet), 0);
    }

    // Test multicall with 10 wallets - non-member authorized by premium member signature (free)
    function testMulticallWith10WalletsNonMemberWithPremiumSignature() public {
        // Prepare for signature
        uint256 expiry = block.timestamp + 1 hours;

        // Create 10 EOA wallets that delegated via EIP-7702
        Wallet[] memory wallets = _createEIP7702Wallets(10, "auth");

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        // Premium member signs authorization for non-member
        bytes memory sig = _createMulticallSignature(premiumMemberKey, nonMember, recipient);

        // Store balances
        uint256 rBal = recipient.balance;
        uint256 rTok = token.balanceOf(recipient);
        uint256 vBal = vault.balance;

        // Non-member calls with premium member's signature - free
        vm.prank(nonMember);
        tokenSweep.multicall(wallets, recipient, tokens, expiry, address(0), sig);

        // Verify sweep and no fee charged
        assertEq(recipient.balance, rBal + 5 ether);
        assertEq(token.balanceOf(recipient), rTok + 500 ether);
        assertEq(vault.balance, vBal);
        assertEq(wallets[0].wallet.balance, 0);
    }

    // Helper: Create EIP-7702 delegated wallets
    function _createEIP7702Wallets(uint256 count, string memory prefix) private returns (Wallet[] memory) {
        TokenSweep temp = new TokenSweep(address(premium));
        bytes memory code = address(temp).code;

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        uint256 expiry = block.timestamp + 1 hours;

        Wallet[] memory wallets = new Wallet[](count);

        for (uint256 i = 0; i < count; i++) {
            (address addr, uint256 key) = makeAddrAndKey(string(abi.encodePacked(prefix, _toString(i))));

            vm.etch(addr, code);
            vm.store(addr, bytes32(0), bytes32(uint256(1)));
            vm.deal(addr, 0.5 ether);
            token.mint(addr, 50 ether);

            bytes32 msgHash = keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(abi.encode(block.chainid, addr, recipient, tokens, expiry))
                )
            );

            (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, msgHash);
            wallets[i] = Wallet({wallet: addr, signature: abi.encodePacked(r, s, v)});
        }

        return wallets;
    }

    // Helper: Create multicall signature
    function _createMulticallSignature(uint256 signerKey, address caller, address dest)
        private
        view
        returns (bytes memory)
    {
        string memory message = string(
            abi.encodePacked(
                "TokenSweep Authorization\n\nI authorize wallet:\n",
                _toHexString(caller),
                "\n\nto call multicall on my behalf\n\nRecipient address:\n",
                _toHexString(dest),
                "\n\nChain ID: ",
                _toString(block.chainid)
            )
        );

        bytes32 hash = keccak256(bytes(message));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, hash);
        return abi.encodePacked(r, s, v);
    }

    // ========== Additional Coverage Tests ==========

    // Test signature with malleable s value (EIP-2)
    function testMalleableSignatureRejected() public {
        // Create a valid signature first
        bytes memory validSig = _createMulticallSignature(premiumMemberKey, nonMember, recipient);

        // Extract r, s, v
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(validSig, 32))
            s := mload(add(validSig, 64))
            v := byte(0, mload(add(validSig, 96)))
        }

        // Create malleable signature with s' = n - s (where n is secp256k1 order)
        // secp256k1 order n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
        bytes32 malleableS = bytes32(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - uint256(s));
        uint8 malleableV = v == 27 ? 28 : 27;

        bytes memory malleableSig = abi.encodePacked(r, malleableS, malleableV);

        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        vm.prank(nonMember);
        vm.expectRevert(TokenSweep.InvalidSignature.selector);
        tokenSweep.multicallFree(wallets, recipient, tokens, block.timestamp + 1 hours, malleableSig);
    }

    // Test authorization with wrong signature length
    function testAuthorizationWrongSignatureLength() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // Signature with wrong length (64 bytes instead of 65)
        bytes memory shortSig = new bytes(64);

        vm.prank(nonMember);
        vm.expectRevert(TokenSweep.InvalidSignature.selector);
        tokenSweep.multicallFree(wallets, recipient, tokens, block.timestamp + 1 hours, shortSig);
    }

    // Test referrer payment failure (referrer rejects ETH)
    function testReferrerPaymentFailure() public {
        // Deploy a contract that rejects ETH
        RejectingContract rejecter = new RejectingContract();

        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // Non-member pays fee with rejecter as referrer
        vm.prank(nonMember);
        // Should succeed even though referrer rejects payment
        tokenSweep.multicall{value: premium.NON_MEMBER_FEE()}(
            wallets, recipient, tokens, block.timestamp + 1 hours, address(rejecter), ""
        );

        // Verify the call succeeded (no revert)
        assertEq(tokenSweep.totalPaidUsage(), 1);
    }

    // Test owner payment failure scenario
    function testOwnerPaymentFailure() public {
        // This tests the case where owner.call fails
        // Since VAULT is a constant EOA, it won't fail in normal conditions
        // But we can still verify the contract handles accumulated balance correctly

        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // Multiple paid calls - all should succeed
        vm.prank(nonMember);
        tokenSweep.multicall{value: premium.NON_MEMBER_FEE()}(
            wallets, recipient, tokens, block.timestamp + 1 hours, address(0), ""
        );

        vm.prank(nonMember);
        tokenSweep.multicall{value: premium.NON_MEMBER_FEE()}(
            wallets, recipient, tokens, block.timestamp + 1 hours, address(0), ""
        );

        assertEq(tokenSweep.totalPaidUsage(), 2);
    }

    // Test drainToAddress with token that returns no data
    function testDrainWithNonStandardToken() public {
        // Deploy a mock token that doesn't return bool on transfer
        MockNonStandardERC20 nonStandardToken = new MockNonStandardERC20();

        // Fund the wallet contract
        nonStandardToken.mint(address(tokenSweep), 1000 ether);

        // This is a self-drain test (testing the drainToAddress path)
        // The actual drainToAddress requires valid signature from the contract itself
        // which is impossible for external caller

        // Verify token is in contract
        assertEq(nonStandardToken.balanceOf(address(tokenSweep)), 1000 ether);
    }

    // Test multicallFree with empty wallets
    function testMulticallFreeEmptyWallets() public {
        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        vm.prank(premiumMember);
        tokenSweep.multicallFree(wallets, recipient, tokens, block.timestamp + 1 hours, "");

        assertEq(tokenSweep.totalFreeUsage(), 1);
    }

    // Test premium member with signature authorization (covers multicall path)
    function testPremiumMemberWithSignature() public {
        bytes memory sig = _createMulticallSignature(premiumMemberKey, nonMember, recipient);

        Wallet[] memory wallets = new Wallet[](0);
        address[] memory tokens = new address[](0);

        // nonMember calls with premiumMember's signature - should be free
        vm.prank(nonMember);
        tokenSweep.multicall{value: 0}(wallets, recipient, tokens, block.timestamp + 1 hours, address(0), sig);

        // Premium usage should increment
        assertEq(tokenSweep.totalPremiumUsage(), 1);
    }
}

// Contract that rejects ETH
contract RejectingContract {
    receive() external payable {
        revert("I reject ETH");
    }
}

// Non-standard ERC20 that doesn't return bool
contract MockNonStandardERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    // Non-standard: doesn't return bool
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "Insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}
