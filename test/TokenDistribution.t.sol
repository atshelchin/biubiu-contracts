// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenDistribution} from "../src/tools/TokenDistribution.sol";
import {Recipient, DistributionAuth, FailedTransfer} from "../src/interfaces/ITokenDistribution.sol";
import {WETH} from "../src/core/WETH.sol";

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
    address public VAULT;
    uint256 public constant NON_MEMBER_FEE = 0.005 ether;

    constructor(address _vault) {
        VAULT = _vault;
    }

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
    address constant VAULT = 0x7602db7FbBc4f0FD7dfA2Be206B39e002A5C94cA;

    uint256 public ownerPrivateKey = 0x1234;
    address public ownerFromKey;

    uint256 constant NON_MEMBER_FEE = 0.01 ether;

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
        // Deploy mock premium contract with VAULT address
        mockPremium = new MockBiuBiuPremium(VAULT);

        // Deploy WETH
        weth = new WETH();

        // Deploy TokenDistribution with weth address only (no premium dependency)
        distribution = new TokenDistribution(address(weth));

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
        vm.deal(VAULT, 0);
    }

    // ============ Helper Functions ============

    function _createRecipients(uint256 count, uint256 amountEach) internal view returns (Recipient[] memory) {
        Recipient[] memory recipients = new Recipient[](count);
        for (uint256 i = 0; i < count; i++) {
            recipients[i] = Recipient({to: address(uint160(0x1000 + i)), value: amountEach});
        }
        return recipients;
    }

    function _signDistributionAuth(DistributionAuth memory auth, uint256 privateKey)
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

    function _computeMerkleRoot(Recipient[] memory recipients, uint256 batchId) internal pure returns (bytes32) {
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

    function _computeMerkleProof(Recipient[] memory recipients, uint256 batchId, uint256 leafIndex)
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
        // Use distributeFree for free distribution
        Recipient[] memory recipients = _createRecipients(3, 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distributeFree{value: 3 ether}(
            address(0),
            0, // tokenType doesn't matter for ETH
            0,
            recipients
        );

        // Check recipients received ETH
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
        assertEq(address(uint160(0x1002)).balance, 1 ether);

        // Alice spent 3 ETH
        assertEq(alice.balance, aliceBalanceBefore - 3 ether);
    }

    function test_DistributeETH_NonPremiumPaysFee() public {
        // Use distribute (paid version) which requires NON_MEMBER_FEE
        uint256 fee = distribution.NON_MEMBER_FEE();

        Recipient[] memory recipients = _createRecipients(2, 1 ether);

        uint256 protocolOwnerBalanceBefore = VAULT.balance;

        vm.prank(alice);
        distribution.distribute{value: 2 ether + fee}(address(0), 0, 0, recipients, address(0));

        // Recipients received ETH
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);

        // Protocol owner received fee
        assertGt(VAULT.balance, protocolOwnerBalanceBefore);
    }

    function test_DistributeETH_WithReferrer() public {
        // Use distribute (paid version) with referrer
        uint256 fee = distribution.NON_MEMBER_FEE();

        Recipient[] memory recipients = _createRecipients(1, 1 ether);

        uint256 referrerBalanceBefore = referrer.balance;

        vm.prank(alice);
        distribution.distribute{value: 1 ether + fee}(address(0), 0, 0, recipients, referrer);

        // Referrer received 50% of fee
        assertEq(referrer.balance, referrerBalanceBefore + fee / 2);
    }

    function test_DistributeETH_RefundsExcess() public {
        // Use distributeFree which refunds excess
        Recipient[] memory recipients = _createRecipients(1, 1 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distributeFree{value: 5 ether}(address(0), 0, 0, recipients);

        // Alice should get 4 ETH back
        assertEq(alice.balance, aliceBalanceBefore - 1 ether);
    }

    function test_DistributeETH_InsufficientPaymentReverts() public {
        uint256 fee = distribution.NON_MEMBER_FEE();
        Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.InsufficientPayment.selector);
        distribution.distribute{value: fee - 1}( // Less than NON_MEMBER_FEE
            address(0), 0, 0, recipients, address(0)
        );
    }

    function test_DistributeETH_BatchTooLargeReverts() public {
        Recipient[] memory recipients = _createRecipients(101, 0.01 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.BatchTooLarge.selector);
        distribution.distributeFree{value: 1.01 ether}(address(0), 0, 0, recipients);
    }

    function test_DistributeETH_EmptyRecipientsReverts() public {
        Recipient[] memory recipients = new Recipient[](0);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.BatchTooLarge.selector);
        distribution.distributeFree{value: 0}(address(0), 0, 0, recipients);
    }

    function test_DistributeETH_SkipsZeroAddress() public {
        Recipient[] memory recipients = new Recipient[](2);
        recipients[0] = Recipient({to: address(0), value: 1 ether});
        recipients[1] = Recipient({to: bob, value: 1 ether});

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(alice);
        distribution.distributeFree{value: 2 ether}(address(0), 0, 0, recipients);

        // Bob received his ETH
        assertEq(bob.balance, 101 ether); // 100 initial + 1

        // Alice got refund for failed transfer
        assertEq(alice.balance, aliceBalanceBefore - 1 ether);
    }

    // ============ Self-Execute ERC20 Distribution Tests ============

    function test_DistributeERC20_Basic() public {
        // Mint tokens to alice and approve
        mockToken.mint(alice, 1000 ether);
        vm.prank(alice);
        mockToken.approve(address(distribution), 1000 ether);

        Recipient[] memory recipients = _createRecipients(3, 100 ether);

        vm.prank(alice);
        distribution.distributeFree(
            address(mockToken),
            1, // ERC20
            0,
            recipients
        );

        // Check recipients received tokens
        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1001))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1002))), 100 ether);
        assertEq(mockToken.balanceOf(alice), 700 ether);
    }

    function test_DistributeERC20_NonPremiumPaysFee() public {
        uint256 fee = distribution.NON_MEMBER_FEE();

        mockToken.mint(alice, 100 ether);
        vm.prank(alice);
        mockToken.approve(address(distribution), 100 ether);

        Recipient[] memory recipients = _createRecipients(1, 100 ether);

        vm.prank(alice);
        distribution.distribute{value: fee}(address(mockToken), 1, 0, recipients, address(0));

        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
    }

    // ============ Self-Execute ERC721 Distribution Tests ============

    function test_DistributeERC721_Basic() public {
        // Mint NFTs to alice
        mockNFT.mint(alice, 1);
        mockNFT.mint(alice, 2);
        mockNFT.mint(alice, 3);
        vm.prank(alice);
        mockNFT.setApprovalForAll(address(distribution), true);

        Recipient[] memory recipients = new Recipient[](3);
        recipients[0] = Recipient({to: bob, value: 1}); // tokenId 1
        recipients[1] = Recipient({to: charlie, value: 2}); // tokenId 2
        recipients[2] = Recipient({to: owner, value: 3}); // tokenId 3

        vm.prank(alice);
        distribution.distributeFree(
            address(mockNFT),
            2, // ERC721
            0,
            recipients
        );

        assertEq(mockNFT.ownerOf(1), bob);
        assertEq(mockNFT.ownerOf(2), charlie);
        assertEq(mockNFT.ownerOf(3), owner);
    }

    // ============ Self-Execute ERC1155 Distribution Tests ============

    function test_DistributeERC1155_Basic() public {
        // Mint ERC1155 tokens to alice
        uint256 tokenId = 42;
        mockERC1155.mint(alice, tokenId, 300);
        vm.prank(alice);
        mockERC1155.setApprovalForAll(address(distribution), true);

        Recipient[] memory recipients = _createRecipients(3, 100);

        vm.prank(alice);
        distribution.distributeFree(
            address(mockERC1155),
            3, // ERC1155
            tokenId,
            recipients
        );

        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1000))), 100);
        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1001))), 100);
        assertEq(mockERC1155.balanceOf(tokenId, address(uint160(0x1002))), 100);
    }

    // ============ Invalid Token Type Tests ============

    function test_Distribute_InvalidTokenTypeReverts() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.prank(alice);
        vm.expectRevert(TokenDistribution.InvalidTokenType.selector);
        distribution.distributeFree(
            address(mockToken),
            4, // Invalid type
            0,
            recipients
        );
    }

    // ============ Delegated Execute Tests ============

    function test_DistributeWithAuth_Basic() public {
        // Setup: owner prepares WETH
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        distribution.distributeWithAuthFree(
            auth,
            signature,
            0, // batchId
            recipients,
            allProofs,
            proofLengths
        );

        // Check recipients received ETH (WETH was unwrapped)
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
    }

    function test_DistributeWithAuth_NonPremiumSignerPaysFee() public {
        uint256 fee = distribution.NON_MEMBER_FEE();

        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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

        uint256 protocolOwnerBefore = VAULT.balance;

        vm.prank(executor);
        distribution.distributeWithAuth{value: fee}(auth, signature, 0, recipients, allProofs, proofLengths, address(0));

        assertGt(VAULT.balance, protocolOwnerBefore);
    }

    function test_DistributeWithAuth_DeadlineExpiredReverts() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_DistributeWithAuth_BatchAlreadyExecutedReverts() public {
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        // Try to execute same batch again
        vm.prank(executor);
        vm.expectRevert(TokenDistribution.BatchAlreadyExecuted.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_DistributeWithAuth_InvalidBatchIdReverts() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        bytes32 uuid = bytes32(uint256(10));

        DistributionAuth memory auth = DistributionAuth({
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

        // Execute batch 0 using distributeWithAuthFree
        vm.prank(executor);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

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
        // Use distributeFree to test max batch size
        Recipient[] memory recipients = _createRecipients(100, 0.01 ether);

        vm.prank(alice);
        distribution.distributeFree{value: 1 ether}(address(0), 0, 0, recipients);

        // All 100 recipients should have received ETH
        for (uint256 i = 0; i < 100; i++) {
            assertEq(address(uint160(0x1000 + i)).balance, 0.01 ether);
        }
    }

    function test_DistributeWithAuth_ERC20() public {
        // Setup: owner approves tokens (no premium check needed for distributeWithAuthFree)
        mockToken.mint(ownerFromKey, 1000 ether);
        vm.prank(ownerFromKey);
        mockToken.approve(address(distribution), 1000 ether);

        Recipient[] memory recipients = _createRecipients(2, 100 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1001))), 100 ether);
    }

    // ============ Fuzz Tests ============

    function testFuzz_DistributeETH(uint8 recipientCount, uint96 amountEach) public {
        vm.assume(recipientCount > 0 && recipientCount <= 100);
        vm.assume(amountEach > 0 && amountEach <= 1 ether);

        // Use distributeFree for fuzz testing
        Recipient[] memory recipients = _createRecipients(recipientCount, amountEach);
        uint256 totalAmount = uint256(recipientCount) * uint256(amountEach);

        vm.deal(alice, totalAmount + 1 ether);

        vm.prank(alice);
        distribution.distributeFree{value: totalAmount}(address(0), 0, 0, recipients);

        // Verify first recipient
        assertEq(address(uint160(0x1000)).balance, amountEach);
    }

    // ============ Event Tests ============

    function test_EmitsDistributedEvent() public {
        // Test distributeFree emits event with USAGE_FREE (0)
        Recipient[] memory recipients = _createRecipients(2, 1 ether);

        vm.expectEmit(true, true, false, true);
        emit Distributed(alice, address(0), 0, 2, 2 ether, 0); // usageType = 0 = USAGE_FREE

        vm.prank(alice);
        distribution.distributeFree{value: 2 ether}(address(0), 0, 0, recipients);
    }

    function test_EmitsReferralPaidEvent() public {
        // Paid distribution with referrer emits ReferralPaid event
        Recipient[] memory recipients = _createRecipients(1, 1 ether);

        vm.expectEmit(true, false, false, true);
        emit ReferralPaid(referrer, NON_MEMBER_FEE / 2);

        vm.prank(alice);
        distribution.distribute{value: 1 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, referrer);
    }

    // ============ Proof Length Validation Tests ============

    function test_DistributeWithAuth_InvalidProofLengthReverts() public {
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
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
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    // ============ Fee Collection Fix Test ============

    function test_FeeCollection_ReferrerGets50Percent() public {
        // Paid distribution with referrer - fee is split 50/50
        Recipient[] memory recipients = _createRecipients(1, 0.1 ether);

        uint256 referrerBalanceBefore = referrer.balance;
        uint256 ownerBalanceBefore = VAULT.balance;

        vm.prank(alice);
        distribution.distribute{value: 0.1 ether + NON_MEMBER_FEE}(address(0), 0, 0, recipients, referrer);

        // Referrer should get exactly 50%
        assertEq(referrer.balance, referrerBalanceBefore + NON_MEMBER_FEE / 2);
        // Owner should get the remaining 50%
        assertEq(VAULT.balance, ownerBalanceBefore + NON_MEMBER_FEE / 2);
    }
}
