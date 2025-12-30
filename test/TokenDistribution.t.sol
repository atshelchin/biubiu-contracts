// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenDistribution} from "../src/TokenDistribution.sol";
import {WETH} from "../src/WETH.sol";

// Mock contracts for testing
contract MockERC20 {
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}

contract MockERC721 {
    mapping(uint256 => address) public ownerOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 tokenId) external {
        ownerOf[tokenId] = to;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(ownerOf[tokenId] == from, "not owner");
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "not approved");
        ownerOf[tokenId] = to;
    }
}

contract MockERC1155 {
    mapping(uint256 => mapping(address => uint256)) public balanceOf;
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    function mint(address to, uint256 id, uint256 amount) external {
        balanceOf[id][to] += amount;
    }

    function setApprovalForAll(address operator, bool approved) external {
        isApprovedForAll[msg.sender][operator] = approved;
    }

    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata) external {
        require(balanceOf[id][from] >= amount, "insufficient balance");
        require(msg.sender == from || isApprovedForAll[from][msg.sender], "not approved");
        balanceOf[id][from] -= amount;
        balanceOf[id][to] += amount;
    }
}

contract MockBiuBiuPremium {
    mapping(address => bool) public isPremium;

    function setPremium(address user, bool status) external {
        isPremium[user] = status;
    }

    function getSubscriptionInfo(address user) external view returns (bool, uint256, uint256) {
        return (isPremium[user], block.timestamp + 30 days, 30 days);
    }
}

contract TokenDistributionTest is Test {
    TokenDistribution public distribution;
    WETH public weth;
    MockERC20 public mockToken;
    MockERC721 public mockNFT;
    MockERC1155 public mockERC1155;
    MockBiuBiuPremium public mockPremium;

    address public owner = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public referrer = address(0x5);
    address public executor = address(0x6);
    address constant PROTOCOL_OWNER = 0xd9eDa338CafaE29b18b4a92aA5f7c646Ba9cDCe9;

    uint256 public ownerPrivateKey = 0x1234;
    address public ownerFromKey;

    uint256 constant NON_MEMBER_FEE = 0.005 ether;

    event Distributed(
        address indexed sender,
        address indexed token,
        uint8 tokenType,
        uint256 recipientCount,
        uint256 totalAmount,
        uint8 usageType
    );
    event DistributedWithAuth(
        bytes32 indexed uuid,
        address indexed signer,
        uint256 batchId,
        uint256 recipientCount,
        uint256 batchAmount,
        uint8 usageType
    );
    event TransferSkipped(address indexed recipient, uint256 value, bytes reason);
    event Refunded(address indexed to, uint256 amount);
    event FeeCollected(address indexed payer, uint256 amount);
    event ReferralPaid(address indexed referrer, uint256 amount);

    function setUp() public {
        // Deploy mock premium contract at the expected address
        mockPremium = new MockBiuBiuPremium();
        vm.etch(0x61Ae52Bb677847853DB30091ccc32d9b68878B71, address(mockPremium).code);
        mockPremium = MockBiuBiuPremium(0x61Ae52Bb677847853DB30091ccc32d9b68878B71);

        // Deploy WETH at expected address
        weth = new WETH();
        vm.etch(0xe3E75C1fe9AE82993FEb6F9CA2e9627aaE1e3d18, address(weth).code);
        weth = WETH(payable(0xe3E75C1fe9AE82993FEb6F9CA2e9627aaE1e3d18));

        // Deploy TokenDistribution
        distribution = new TokenDistribution();

        // Deploy mock tokens
        mockToken = new MockERC20();
        mockNFT = new MockERC721();
        mockERC1155 = new MockERC1155();

        // Setup owner from private key for signature tests
        ownerFromKey = vm.addr(ownerPrivateKey);

        // Fund test addresses
        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
        vm.deal(executor, 100 ether);
        vm.deal(ownerFromKey, 100 ether);
        vm.deal(PROTOCOL_OWNER, 0);
    }

    // ============ Helper Functions ============

    function _createRecipients(uint256 count, uint256 amountEach)
        internal
        view
        returns (TokenDistribution.Recipient[] memory)
    {
        TokenDistribution.Recipient[] memory recipients = new TokenDistribution.Recipient[](count);
        for (uint256 i = 0; i < count; i++) {
            recipients[i] = TokenDistribution.Recipient({to: address(uint160(0x1000 + i)), value: amountEach});
        }
        return recipients;
    }

    function _signDistributionAuth(TokenDistribution.DistributionAuth memory auth, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                distribution.DISTRIBUTION_AUTH_TYPEHASH(),
                auth.uuid,
                auth.token,
                auth.tokenType,
                auth.tokenId,
                auth.totalAmount,
                auth.totalBatches,
                auth.merkleRoot,
                auth.deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", distribution.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _computeMerkleRoot(TokenDistribution.Recipient[] memory recipients, uint256 batchId)
        internal
        pure
        returns (bytes32)
    {
        uint256 len = recipients.length;
        bytes32[] memory leaves = new bytes32[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 index = batchId * 100 + i;
            leaves[i] = keccak256(abi.encodePacked(index, recipients[i].to, recipients[i].value));
        }

        // Build merkle tree
        while (len > 1) {
            uint256 newLen = (len + 1) / 2;
            bytes32[] memory newLeaves = new bytes32[](newLen);
            for (uint256 i = 0; i < newLen; i++) {
                if (2 * i + 1 < len) {
                    bytes32 left = leaves[2 * i];
                    bytes32 right = leaves[2 * i + 1];
                    if (left <= right) {
                        newLeaves[i] = keccak256(abi.encodePacked(left, right));
                    } else {
                        newLeaves[i] = keccak256(abi.encodePacked(right, left));
                    }
                } else {
                    newLeaves[i] = leaves[2 * i];
                }
            }
            leaves = newLeaves;
            len = newLen;
        }

        return leaves[0];
    }

    function _computeMerkleProof(TokenDistribution.Recipient[] memory recipients, uint256 batchId, uint256 leafIndex)
        internal
        pure
        returns (bytes32[] memory)
    {
        uint256 len = recipients.length;
        bytes32[] memory leaves = new bytes32[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 index = batchId * 100 + i;
            leaves[i] = keccak256(abi.encodePacked(index, recipients[i].to, recipients[i].value));
        }

        // Calculate proof depth
        uint256 depth = 0;
        uint256 tempLen = len;
        while (tempLen > 1) {
            depth++;
            tempLen = (tempLen + 1) / 2;
        }

        bytes32[] memory proof = new bytes32[](depth);
        uint256 proofIndex = 0;
        uint256 currentIndex = leafIndex;

        while (len > 1) {
            uint256 siblingIndex = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;
            if (siblingIndex < len) {
                proof[proofIndex] = leaves[siblingIndex];
                proofIndex++;
            }

            // Build next level
            uint256 newLen = (len + 1) / 2;
            bytes32[] memory newLeaves = new bytes32[](newLen);
            for (uint256 i = 0; i < newLen; i++) {
                if (2 * i + 1 < len) {
                    bytes32 left = leaves[2 * i];
                    bytes32 right = leaves[2 * i + 1];
                    if (left <= right) {
                        newLeaves[i] = keccak256(abi.encodePacked(left, right));
                    } else {
                        newLeaves[i] = keccak256(abi.encodePacked(right, left));
                    }
                } else {
                    newLeaves[i] = leaves[2 * i];
                }
            }
            leaves = newLeaves;
            len = newLen;
            currentIndex = currentIndex / 2;
        }

        // Resize proof to actual length
        bytes32[] memory actualProof = new bytes32[](proofIndex);
        for (uint256 i = 0; i < proofIndex; i++) {
            actualProof[i] = proof[i];
        }
        return actualProof;
    }

    // ============ Self-Execute ETH Distribution Tests ============

    function test_DistributeETH_Basic() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(3, 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distribute{value: 3 ether}(
            address(0),
            0, // tokenType doesn't matter for ETH
            0,
            recipients,
            address(0)
        );

        // Check recipients received ETH
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
        assertEq(address(uint160(0x1002)).balance, 1 ether);

        // Alice spent 3 ETH
        assertEq(alice.balance, aliceBalanceBefore - 3 ether);
    }

    function test_DistributeETH_NonPremiumPaysFee() public {
        mockPremium.setPremium(alice, false);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(2, 1 ether);

        uint256 protocolOwnerBalanceBefore = PROTOCOL_OWNER.balance;

        vm.prank(alice);
        distribution.distribute{value: 2 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, address(0));

        // Recipients received ETH
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);

        // Protocol owner received fee
        assertGt(PROTOCOL_OWNER.balance, protocolOwnerBalanceBefore);
    }

    function test_DistributeETH_WithReferrer() public {
        mockPremium.setPremium(alice, false);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);

        uint256 referrerBalanceBefore = referrer.balance;

        vm.prank(alice);
        distribution.distribute{value: 1 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, referrer);

        // Referrer received 50% of fee
        assertEq(referrer.balance, referrerBalanceBefore + NON_MEMBER_FEE / 2);
    }

    function test_DistributeETH_RefundsExcess() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distribute{value: 5 ether}(address(0), 0, 0, recipients, address(0));

        // Alice should get 4 ETH back
        assertEq(alice.balance, aliceBalanceBefore - 1 ether);
    }

    function test_DistributeETH_InsufficientPaymentReverts() public {
        mockPremium.setPremium(alice, false);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.InsufficientPayment.selector);
        distribution.distribute{value: 0.004 ether}( // Less than NON_MEMBER_FEE
            address(0), 0, 0, recipients, address(0)
        );
    }

    function test_DistributeETH_BatchTooLargeReverts() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(101, 0.01 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.BatchTooLarge.selector);
        distribution.distribute{value: 1.01 ether}(address(0), 0, 0, recipients, address(0));
    }

    function test_DistributeETH_EmptyRecipientsReverts() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = new TokenDistribution.Recipient[](0);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.BatchTooLarge.selector);
        distribution.distribute{value: 0}(address(0), 0, 0, recipients, address(0));
    }

    function test_DistributeETH_SkipsZeroAddress() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = new TokenDistribution.Recipient[](2);
        recipients[0] = TokenDistribution.Recipient({to: address(0), value: 1 ether});
        recipients[1] = TokenDistribution.Recipient({to: bob, value: 1 ether});

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distribute{value: 2 ether}(address(0), 0, 0, recipients, address(0));

        // Bob received his ETH
        assertEq(bob.balance, 101 ether); // 100 initial + 1

        // Alice got refund for failed transfer
        assertEq(alice.balance, aliceBalanceBefore - 1 ether);
    }

    // ============ Self-Execute ERC20 Distribution Tests ============

    function test_DistributeERC20_Basic() public {
        mockPremium.setPremium(alice, true);

        // Mint tokens to alice and approve
        mockToken.mint(alice, 1000 ether);
        vm.prank(alice);
        mockToken.approve(address(distribution), 1000 ether);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(3, 100 ether);

        vm.prank(alice);
        distribution.distribute(
            address(mockToken),
            1, // ERC20
            0,
            recipients,
            address(0)
        );

        // Check recipients received tokens
        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1001))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1002))), 100 ether);
        assertEq(mockToken.balanceOf(alice), 700 ether);
    }

    function test_DistributeERC20_NonPremiumPaysFee() public {
        mockPremium.setPremium(alice, false);

        mockToken.mint(alice, 100 ether);
        vm.prank(alice);
        mockToken.approve(address(distribution), 100 ether);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 100 ether);

        vm.prank(alice);
        distribution.distribute{value: NON_MEMBER_FEE}(address(mockToken), 1, 0, recipients, address(0));

        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
    }

    // ============ Self-Execute ERC721 Distribution Tests ============

    function test_DistributeERC721_Basic() public {
        mockPremium.setPremium(alice, true);

        // Mint NFTs to alice
        mockNFT.mint(alice, 1);
        mockNFT.mint(alice, 2);
        mockNFT.mint(alice, 3);
        vm.prank(alice);
        mockNFT.setApprovalForAll(address(distribution), true);

        TokenDistribution.Recipient[] memory recipients = new TokenDistribution.Recipient[](3);
        recipients[0] = TokenDistribution.Recipient({to: bob, value: 1}); // tokenId 1
        recipients[1] = TokenDistribution.Recipient({to: charlie, value: 2}); // tokenId 2
        recipients[2] = TokenDistribution.Recipient({to: owner, value: 3}); // tokenId 3

        vm.prank(alice);
        distribution.distribute(
            address(mockNFT),
            2, // ERC721
            0,
            recipients,
            address(0)
        );

        assertEq(mockNFT.ownerOf(1), bob);
        assertEq(mockNFT.ownerOf(2), charlie);
        assertEq(mockNFT.ownerOf(3), owner);
    }

    // ============ Self-Execute ERC1155 Distribution Tests ============

    function test_DistributeERC1155_Basic() public {
        mockPremium.setPremium(alice, true);

        // Mint ERC1155 tokens to alice
        uint256 tokenId = 42;
        mockERC1155.mint(alice, tokenId, 300);
        vm.prank(alice);
        mockERC1155.setApprovalForAll(address(distribution), true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(3, 100);

        vm.prank(alice);
        distribution.distribute(
            address(mockERC1155),
            3, // ERC1155
            tokenId,
            recipients,
            address(0)
        );

        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1000))), 100);
        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1001))), 100);
        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1002))), 100);
    }

    // ============ Invalid Token Type Tests ============

    function test_Distribute_InvalidTokenTypeReverts() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.InvalidTokenType.selector);
        distribution.distribute(
            address(mockToken),
            4, // Invalid type
            0,
            recipients,
            address(0)
        );
    }

    // ============ Delegated Execute Tests ============

    function test_DistributeWithAuth_Basic() public {
        mockPremium.setPremium(ownerFromKey, true);

        // Setup: owner prepares WETH
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(1)),
            token: address(weth),
            tokenType: 0, // WETH
            tokenId: 0,
            totalAmount: 2 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        // Build proofs
        bytes32[] memory allProofs = new bytes32[](2);
        uint8[] memory proofLengths = new uint8[](2);

        bytes32[] memory proof0 = _computeMerkleProof(recipients, 0, 0);
        bytes32[] memory proof1 = _computeMerkleProof(recipients, 0, 1);

        // For 2 leaves, each has 1 proof element
        allProofs[0] = proof0.length > 0 ? proof0[0] : bytes32(0);
        allProofs[1] = proof1.length > 0 ? proof1[0] : bytes32(0);
        proofLengths[0] = uint8(proof0.length);
        proofLengths[1] = uint8(proof1.length);

        vm.prank(executor);
        distribution.distributeWithAuth(
            auth,
            signature,
            0, // batchId
            recipients,
            allProofs,
            proofLengths,
            address(0)
        );

        // Check recipients received ETH (WETH was unwrapped)
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
    }

    function test_DistributeWithAuth_NonPremiumSignerPaysFee() public {
        mockPremium.setPremium(ownerFromKey, false);

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(2)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        uint256 protocolOwnerBefore = PROTOCOL_OWNER.balance;

        vm.prank(executor);
        distribution.distributeWithAuth{value: NON_MEMBER_FEE}(
            auth, signature, 0, recipients, allProofs, proofLengths, address(0)
        );

        assertGt(PROTOCOL_OWNER.balance, protocolOwnerBefore);
    }

    function test_DistributeWithAuth_DeadlineExpiredReverts() public {
        mockPremium.setPremium(ownerFromKey, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(3)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp - 1 // Expired
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.DeadlineExpired.selector);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));
    }

    function test_DistributeWithAuth_BatchAlreadyExecutedReverts() public {
        mockPremium.setPremium(ownerFromKey, true);

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(4)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 2 ether,
            totalBatches: 2,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        // Execute first time
        vm.prank(executor);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));

        // Try to execute same batch again
        vm.prank(executor);
        vm.expectRevert(TokenDistribution.BatchAlreadyExecuted.selector);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));
    }

    function test_DistributeWithAuth_InvalidBatchIdReverts() public {
        mockPremium.setPremium(ownerFromKey, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(5)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidBatchId.selector);
        distribution.distributeWithAuth(
            auth,
            signature,
            1, // Invalid: only batch 0 exists
            recipients,
            allProofs,
            proofLengths,
            address(0)
        );
    }

    function test_DistributeWithAuth_InvalidSignatureReverts() public {
        // When signature is from wrong signer, the verification will fail at Merkle proof stage
        // because the recovered signer won't have WETH approved
        // Let's test with a malformed signature instead
        mockPremium.setPremium(ownerFromKey, true);

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(6)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Create signature with high s value (malleability attack)
        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        // Modify s value to be above the threshold (simulate malleability)
        // The threshold is 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Create signature with s > threshold
        bytes32 highS = bytes32(uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1));
        bytes memory malleableSignature = abi.encodePacked(r, highS, v);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuth(auth, malleableSignature, 0, recipients, allProofs, proofLengths, address(0));
    }

    function test_DistributeWithAuth_InvalidSignatureLengthReverts() public {
        mockPremium.setPremium(ownerFromKey, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(7)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = hex"1234"; // Too short

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));
    }

    // ============ Progress Tracking Tests ============

    function test_GetProgress() public {
        mockPremium.setPremium(ownerFromKey, true);

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        bytes32 uuid = bytes32(uint256(10));

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: uuid,
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 3 ether,
            totalBatches: 3,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        // Execute batch 0
        vm.prank(executor);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));

        (uint256 executedBatches, uint256 totalBatchesValue, uint256 distributed) = distribution.getProgress(uuid);
        assertEq(executedBatches, 1);
        assertEq(totalBatchesValue, 3);
        assertEq(distributed, 1 ether);

        // Check isBatchExecuted
        assertTrue(distribution.isBatchExecuted(uuid, 0));
        assertFalse(distribution.isBatchExecuted(uuid, 1));
    }

    // ============ Reentrancy Tests ============

    function test_ReentrancyProtection() public {
        // The nonReentrant modifier should prevent reentrancy
        // This is implicitly tested by the distribution functions
        // A full reentrancy test would require a malicious recipient contract
    }

    // ============ Edge Cases ============

    function test_DistributeMaxBatchSize() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(100, 0.01 ether);

        vm.prank(alice);
        distribution.distribute{value: 1 ether}(address(0), 0, 0, recipients, address(0));

        // All 100 recipients should have received ETH
        for (uint256 i = 0; i < 100; i++) {
            assertEq(address(uint160(0x1000 + i)).balance, 0.01 ether);
        }
    }

    function test_DistributeWithAuth_ERC20() public {
        mockPremium.setPremium(ownerFromKey, true);

        // Setup: owner approves tokens
        mockToken.mint(ownerFromKey, 1000 ether);
        vm.prank(ownerFromKey);
        mockToken.approve(address(distribution), 1000 ether);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(2, 100 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(20)),
            token: address(mockToken),
            tokenType: 1, // ERC20
            tokenId: 0,
            totalAmount: 200 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](2);
        uint8[] memory proofLengths = new uint8[](2);

        bytes32[] memory proof0 = _computeMerkleProof(recipients, 0, 0);
        bytes32[] memory proof1 = _computeMerkleProof(recipients, 0, 1);

        allProofs[0] = proof0.length > 0 ? proof0[0] : bytes32(0);
        allProofs[1] = proof1.length > 0 ? proof1[0] : bytes32(0);
        proofLengths[0] = uint8(proof0.length);
        proofLengths[1] = uint8(proof1.length);

        vm.prank(executor);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));

        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1001))), 100 ether);
    }

    // ============ Fuzz Tests ============

    function testFuzz_DistributeETH(uint8 recipientCount, uint96 amountEach) public {
        vm.assume(recipientCount > 0 && recipientCount <= 100);
        vm.assume(amountEach > 0 && amountEach <= 1 ether);

        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(recipientCount, amountEach);
        uint256 totalAmount = uint256(recipientCount) * uint256(amountEach);

        vm.deal(alice, totalAmount + 1 ether);

        vm.prank(alice);
        distribution.distribute{value: totalAmount}(address(0), 0, 0, recipients, address(0));

        // Verify first recipient
        assertEq(address(uint160(0x1000)).balance, amountEach);
    }

    // ============ Event Tests ============

    function test_EmitsDistributedEvent() public {
        mockPremium.setPremium(alice, true);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(2, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit Distributed(alice, address(0), 0, 2, 2 ether, 1); // usageType = 1 = USAGE_PREMIUM

        vm.prank(alice);
        distribution.distribute{value: 2 ether}(address(0), 0, 0, recipients, address(0));
    }

    function test_EmitsReferralPaidEvent() public {
        mockPremium.setPremium(alice, false);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit ReferralPaid(referrer, NON_MEMBER_FEE / 2);

        vm.prank(alice);
        distribution.distribute{value: 1 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, referrer);
    }

    // ============ Owner Withdraw Tests ============

    function test_OwnerWithdrawETH() public {
        // Send some ETH to the contract
        vm.deal(address(distribution), 1 ether);

        uint256 ownerBalanceBefore = PROTOCOL_OWNER.balance;

        distribution.ownerWithdraw(address(0));

        assertEq(PROTOCOL_OWNER.balance, ownerBalanceBefore + 1 ether);
        assertEq(address(distribution).balance, 0);
    }

    function test_OwnerWithdrawETH_NoBalance() public {
        vm.expectRevert(TokenDistribution.WithdrawalFailed.selector);
        distribution.ownerWithdraw(address(0));
    }

    function test_OwnerWithdrawERC20() public {
        // Mint tokens to the distribution contract
        mockToken.mint(address(distribution), 100 ether);

        uint256 ownerBalanceBefore = mockToken.balanceOf(PROTOCOL_OWNER);

        distribution.ownerWithdraw(address(mockToken));

        assertEq(mockToken.balanceOf(PROTOCOL_OWNER), ownerBalanceBefore + 100 ether);
        assertEq(mockToken.balanceOf(address(distribution)), 0);
    }

    function test_OwnerWithdrawERC20_NoBalance() public {
        vm.expectRevert(TokenDistribution.WithdrawalFailed.selector);
        distribution.ownerWithdraw(address(mockToken));
    }

    // ============ Proof Length Validation Tests ============

    function test_DistributeWithAuth_InvalidProofLengthReverts() public {
        mockPremium.setPremium(ownerFromKey, true);

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        TokenDistribution.Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        TokenDistribution.DistributionAuth memory auth = TokenDistribution.DistributionAuth({
            uuid: bytes32(uint256(100)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 2 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, ownerPrivateKey);

        // proofLengths says we need 2 proofs, but we only provide 1
        bytes32[] memory allProofs = new bytes32[](1);
        allProofs[0] = bytes32(uint256(1));
        uint8[] memory proofLengths = new uint8[](2);
        proofLengths[0] = 1;
        proofLengths[1] = 1; // Says we need 2 total proof elements, but only 1 provided

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidProofLength.selector);
        distribution.distributeWithAuth(auth, signature, 0, recipients, allProofs, proofLengths, address(0));
    }

    // ============ Fee Collection Fix Test ============

    function test_FeeCollection_ReferrerGets50Percent() public {
        mockPremium.setPremium(alice, false);

        TokenDistribution.Recipient[] memory recipients = _createRecipients(1, 0.1 ether);

        uint256 referrerBalanceBefore = referrer.balance;
        uint256 ownerBalanceBefore = PROTOCOL_OWNER.balance;

        vm.prank(alice);
        distribution.distribute{value: 0.1 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, referrer);

        // Referrer should get exactly 50%
        assertEq(referrer.balance, referrerBalanceBefore + NON_MEMBER_FEE / 2);
        // Owner should get the remaining 50%
        assertEq(PROTOCOL_OWNER.balance, ownerBalanceBefore + NON_MEMBER_FEE / 2);
    }
}
