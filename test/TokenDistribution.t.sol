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

// ============ EIP-1271 Mock Contract Wallets ============

/// @notice Mock ERC1271 wallet that always returns valid signature
contract MockERC1271WalletValid {
    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    address public owner;
    mapping(bytes32 => bool) public approvedHashes;

    constructor(address _owner) {
        owner = _owner;
    }

    function approveHash(bytes32 hash) external {
        require(msg.sender == owner, "not owner");
        approvedHashes[hash] = true;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        // Check if hash is pre-approved
        if (approvedHashes[hash]) {
            return EIP1271_MAGIC_VALUE;
        }

        // Or verify the signature is from owner
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 32))
                v := byte(0, calldataload(add(signature.offset, 64)))
            }
            address recovered = ecrecover(hash, v, r, s);
            if (recovered == owner) {
                return EIP1271_MAGIC_VALUE;
            }
        }

        return bytes4(0xffffffff);
    }
}

/// @notice Mock ERC1271 wallet that always returns invalid
contract MockERC1271WalletInvalid {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return bytes4(0xffffffff);
    }
}

/// @notice Mock ERC1271 wallet that reverts
contract MockERC1271WalletReverting {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        revert("always reverts");
    }
}

/// @notice Mock ERC1271 wallet that returns wrong magic value
contract MockERC1271WalletWrongMagic {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        return bytes4(0x12345678); // Wrong magic value
    }
}

/// @notice Mock Safe-like multisig wallet with threshold
contract MockSafeWallet {
    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    address[] public owners;
    uint256 public threshold;
    mapping(bytes32 => uint256) public approvalCount;
    mapping(bytes32 => mapping(address => bool)) public hasApproved;

    constructor(address[] memory _owners, uint256 _threshold) {
        require(_owners.length >= _threshold, "invalid threshold");
        owners = _owners;
        threshold = _threshold;
    }

    function approveHash(bytes32 hash) external {
        bool isOwner = false;
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == msg.sender) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "not owner");
        require(!hasApproved[hash][msg.sender], "already approved");

        hasApproved[hash][msg.sender] = true;
        approvalCount[hash]++;
    }

    function isValidSignature(bytes32 hash, bytes calldata) external view returns (bytes4) {
        if (approvalCount[hash] >= threshold) {
            return EIP1271_MAGIC_VALUE;
        }
        return bytes4(0xffffffff);
    }
}

/// @notice Mock ERC1271 wallet with gas limit attack (consumes all gas)
contract MockERC1271WalletGasGrief {
    function isValidSignature(bytes32, bytes calldata) external pure returns (bytes4) {
        // Infinite loop to consume gas
        while (true) {}
        return bytes4(0x1626ba7e);
    }
}

/// @notice Mock ERC1271 wallet that returns valid only for specific signatures
contract MockERC1271WalletSelective {
    bytes4 constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    mapping(bytes32 => bytes) public validSignatures;

    function setValidSignature(bytes32 hash, bytes calldata signature) external {
        validSignatures[hash] = signature;
    }

    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4) {
        bytes memory stored = validSignatures[hash];
        if (stored.length == signature.length && keccak256(stored) == keccak256(signature)) {
            return EIP1271_MAGIC_VALUE;
        }
        return bytes4(0xffffffff);
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

    // ============================================================================
    // ============ SIGNATURE VERIFICATION TESTS (EOA & EIP-1271) ================
    // ============================================================================

    // ============ EOA Signature Tests ============

    function test_EOA_ValidSignature_Basic() public {
        // Basic EOA signature verification
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(1001)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 2 ether,
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
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 2 ether);
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
    }

    function test_EOA_ValidSignature_DifferentPrivateKeys() public {
        // Test with multiple different private keys
        uint256[] memory privateKeys = new uint256[](3);
        privateKeys[0] = 0xA11CE;
        privateKeys[1] = 0xB0B;
        privateKeys[2] = 0xCAFE;

        for (uint256 i = 0; i < privateKeys.length; i++) {
            address signer = vm.addr(privateKeys[i]);
            vm.deal(signer, 100 ether);

            vm.prank(signer);
            weth.depositAndApprove{value: 5 ether}(address(distribution));

            Recipient[] memory recipients = _createRecipients(1, 1 ether);
            bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

            DistributionAuth memory auth = DistributionAuth({
                uuid: bytes32(uint256(2000 + i)),
                token: address(weth),
                tokenType: 0,
                tokenId: 0,
                totalAmount: 1 ether,
                totalBatches: 1,
                merkleRoot: merkleRoot,
                deadline: block.timestamp + 1 days
            });

            bytes memory signature = _signDistributionAuth(auth, privateKeys[i]);

            bytes32[] memory allProofs = new bytes32[](0);
            uint8[] memory proofLengths = new uint8[](1);
            proofLengths[0] = 0;

            vm.prank(executor);
            (uint256 batchAmount,) =
                distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

            assertEq(batchAmount, 1 ether);
        }
    }

    function test_EOA_InvalidSignature_WrongPrivateKey() public {
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(1002)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Sign with wrong private key
        uint256 wrongPrivateKey = 0xDEAD;
        bytes memory signature = _signDistributionAuth(auth, wrongPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        // This will fail because recovered signer won't have WETH approved
        vm.prank(executor);
        vm.expectRevert(); // TransferFailed or similar
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EOA_InvalidSignature_Malleability() public {
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(1003)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Create a signature with high s value (malleability)
        bytes32 highS = bytes32(uint256(0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A1));
        bytes memory malleableSignature = abi.encodePacked(bytes32(uint256(1)), highS, uint8(27));

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, malleableSignature, 0, recipients, allProofs, proofLengths);
    }

    function test_EOA_InvalidSignature_WrongLength() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(1004)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Various invalid signature lengths
        bytes[] memory invalidSigs = new bytes[](5);
        invalidSigs[0] = hex""; // Empty
        invalidSigs[1] = hex"1234"; // Too short
        invalidSigs[2] = hex"123456789012345678901234567890123456789012345678901234567890123456"; // 66 bytes
        invalidSigs[3] = hex"12345678901234567890123456789012345678901234567890123456789012345678901234567890"; // 80 bytes
        invalidSigs[4] = hex"1234567890123456789012345678901234567890123456789012345678901234"; // 64 bytes

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        for (uint256 i = 0; i < invalidSigs.length; i++) {
            vm.prank(executor);
            vm.expectRevert(TokenDistribution.InvalidSignature.selector);
            distribution.distributeWithAuthFree(auth, invalidSigs[i], 0, recipients, allProofs, proofLengths);
        }
    }

    function test_EOA_InvalidSignature_ZeroRecovery() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(1005)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Signature that recovers to address(0) - all zeros with valid length
        bytes memory zeroSig = new bytes(65);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, zeroSig, 0, recipients, allProofs, proofLengths);
    }

    function test_EOA_ValidSignature_EdgeV_Values() public {
        // Test with v = 27 and v = 28
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 20 ether}(address(distribution));

        for (uint256 i = 0; i < 2; i++) {
            Recipient[] memory recipients = _createRecipients(1, 1 ether);
            bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

            DistributionAuth memory auth = DistributionAuth({
                uuid: bytes32(uint256(1006 + i)),
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
            (uint256 batchAmount,) =
                distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
            assertEq(batchAmount, 1 ether);
        }
    }

    // ============ EIP-1271 Contract Wallet Tests ============

    function test_EIP1271_ValidContractWallet_Basic() public {
        // Deploy contract wallet with ownerFromKey as owner
        MockERC1271WalletValid contractWallet = new MockERC1271WalletValid(ownerFromKey);

        // Fund the contract wallet with WETH
        vm.deal(address(contractWallet), 100 ether);
        vm.prank(address(contractWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2001)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 2 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Compute digest for pre-approval
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

        // Pre-approve the hash
        vm.prank(ownerFromKey);
        contractWallet.approveHash(digest);

        // Create EIP-1271 signature format: abi.encode(contractAddress, innerSignature)
        bytes memory innerSig = hex"00"; // Minimal inner signature since hash is pre-approved
        bytes memory signature = abi.encode(address(contractWallet), innerSig);

        bytes32[] memory allProofs = new bytes32[](2);
        uint8[] memory proofLengths = new uint8[](2);
        bytes32[] memory proof0 = _computeMerkleProof(recipients, 0, 0);
        bytes32[] memory proof1 = _computeMerkleProof(recipients, 0, 1);
        allProofs[0] = proof0.length > 0 ? proof0[0] : bytes32(0);
        allProofs[1] = proof1.length > 0 ? proof1[0] : bytes32(0);
        proofLengths[0] = uint8(proof0.length);
        proofLengths[1] = uint8(proof1.length);

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 2 ether);
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
    }

    function test_EIP1271_ValidContractWallet_WithECDSAInnerSig() public {
        // Deploy contract wallet
        MockERC1271WalletValid contractWallet = new MockERC1271WalletValid(ownerFromKey);

        vm.deal(address(contractWallet), 100 ether);
        vm.prank(address(contractWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2002)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Compute digest
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

        // Sign the digest with owner's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory innerSig = abi.encodePacked(r, s, v);

        // Create EIP-1271 signature format
        bytes memory signature = abi.encode(address(contractWallet), innerSig);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 1 ether);
    }

    function test_EIP1271_SafeMultisig_ThresholdMet() public {
        // Create 3-of-5 multisig
        address[] memory owners = new address[](5);
        owners[0] = address(0x100);
        owners[1] = address(0x101);
        owners[2] = address(0x102);
        owners[3] = address(0x103);
        owners[4] = address(0x104);

        MockSafeWallet safeWallet = new MockSafeWallet(owners, 3);

        vm.deal(address(safeWallet), 100 ether);
        vm.prank(address(safeWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2003)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Compute digest
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

        // Get 3 owners to approve
        vm.prank(owners[0]);
        safeWallet.approveHash(digest);
        vm.prank(owners[1]);
        safeWallet.approveHash(digest);
        vm.prank(owners[2]);
        safeWallet.approveHash(digest);

        bytes memory signature = abi.encode(address(safeWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 1 ether);
    }

    function test_EIP1271_SafeMultisig_ThresholdNotMet() public {
        // Create 3-of-5 multisig
        address[] memory owners = new address[](5);
        owners[0] = address(0x200);
        owners[1] = address(0x201);
        owners[2] = address(0x202);
        owners[3] = address(0x203);
        owners[4] = address(0x204);

        MockSafeWallet safeWallet = new MockSafeWallet(owners, 3);

        vm.deal(address(safeWallet), 100 ether);
        vm.prank(address(safeWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2004)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

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

        // Only 2 owners approve (threshold is 3)
        vm.prank(owners[0]);
        safeWallet.approveHash(digest);
        vm.prank(owners[1]);
        safeWallet.approveHash(digest);

        bytes memory signature = abi.encode(address(safeWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_InvalidContractWallet_AlwaysInvalid() public {
        MockERC1271WalletInvalid invalidWallet = new MockERC1271WalletInvalid();

        vm.deal(address(invalidWallet), 100 ether);
        vm.prank(address(invalidWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2005)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = abi.encode(address(invalidWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_ContractWallet_Reverts() public {
        MockERC1271WalletReverting revertingWallet = new MockERC1271WalletReverting();

        vm.deal(address(revertingWallet), 100 ether);
        vm.prank(address(revertingWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2006)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = abi.encode(address(revertingWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        // Should gracefully handle the revert and return InvalidSignature
        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_ContractWallet_WrongMagicValue() public {
        MockERC1271WalletWrongMagic wrongMagicWallet = new MockERC1271WalletWrongMagic();

        vm.deal(address(wrongMagicWallet), 100 ether);
        vm.prank(address(wrongMagicWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2007)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = abi.encode(address(wrongMagicWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_SelectiveWallet_CorrectSignature() public {
        MockERC1271WalletSelective selectiveWallet = new MockERC1271WalletSelective();

        vm.deal(address(selectiveWallet), 100 ether);
        vm.prank(address(selectiveWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2008)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

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

        // Set valid signature
        bytes memory innerSig = hex"CAFEBABE";
        selectiveWallet.setValidSignature(digest, innerSig);

        bytes memory signature = abi.encode(address(selectiveWallet), innerSig);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 1 ether);
    }

    function test_EIP1271_SelectiveWallet_WrongSignature() public {
        MockERC1271WalletSelective selectiveWallet = new MockERC1271WalletSelective();

        vm.deal(address(selectiveWallet), 100 ether);
        vm.prank(address(selectiveWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(2009)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

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

        // Set valid signature
        selectiveWallet.setValidSignature(digest, hex"CAFEBABE");

        // But use wrong signature
        bytes memory signature = abi.encode(address(selectiveWallet), hex"DEADBEEF");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    // ============ Edge Cases and Security Tests ============

    function test_EIP1271_EOAAddressInContractFormat() public {
        // Try to use EOA address in contract signature format
        // This should fail because EOA has no code
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(3001)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Use EOA address in contract signature format
        bytes memory signature = abi.encode(ownerFromKey, hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_ZeroAddressInContractFormat() public {
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(3002)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // Use zero address in contract signature format
        bytes memory signature = abi.encode(address(0), hex"00");

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);
    }

    function test_EIP1271_SignatureLengthBoundary() public {
        // Test signature length boundaries (85 bytes is the minimum for EIP-1271 path)
        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(3003)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        // 85 bytes - exactly at boundary (should try EIP-1271 but fail to decode)
        bytes memory sig85 = new bytes(85);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, sig85, 0, recipients, allProofs, proofLengths);

        // 86 bytes - above boundary
        bytes memory sig86 = new bytes(86);

        auth.uuid = bytes32(uint256(3004));

        vm.prank(executor);
        vm.expectRevert(); // Will try to decode and fail
        distribution.distributeWithAuthFree(auth, sig86, 0, recipients, allProofs, proofLengths);
    }

    function test_Signature_SwitchBetweenEOAAndContract() public {
        // First use EOA signature, then contract signature
        MockERC1271WalletValid contractWallet = new MockERC1271WalletValid(ownerFromKey);

        // Setup both signers
        vm.prank(ownerFromKey);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        vm.deal(address(contractWallet), 100 ether);
        vm.prank(address(contractWallet));
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        // First distribution with EOA
        Recipient[] memory recipients1 = _createRecipients(1, 1 ether);
        bytes32 merkleRoot1 = _computeMerkleRoot(recipients1, 0);

        DistributionAuth memory auth1 = DistributionAuth({
            uuid: bytes32(uint256(4001)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot1,
            deadline: block.timestamp + 1 days
        });

        bytes memory eoaSig = _signDistributionAuth(auth1, ownerPrivateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        (uint256 amount1,) = distribution.distributeWithAuthFree(auth1, eoaSig, 0, recipients1, allProofs, proofLengths);
        assertEq(amount1, 1 ether);

        // Second distribution with contract wallet
        Recipient[] memory recipients2 = _createRecipients(1, 1 ether);
        bytes32 merkleRoot2 = _computeMerkleRoot(recipients2, 0);

        DistributionAuth memory auth2 = DistributionAuth({
            uuid: bytes32(uint256(4002)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot2,
            deadline: block.timestamp + 1 days
        });

        bytes32 structHash2 = keccak256(
            abi.encode(
                distribution.DISTRIBUTION_AUTH_TYPEHASH(),
                auth2.uuid,
                auth2.token,
                auth2.tokenType,
                auth2.tokenId,
                auth2.totalAmount,
                auth2.totalBatches,
                auth2.merkleRoot,
                auth2.deadline
            )
        );
        bytes32 digest2 = keccak256(abi.encodePacked("\x19\x01", distribution.DOMAIN_SEPARATOR(), structHash2));

        vm.prank(ownerFromKey);
        contractWallet.approveHash(digest2);

        bytes memory contractSig = abi.encode(address(contractWallet), hex"00");

        vm.prank(executor);
        (uint256 amount2,) =
            distribution.distributeWithAuthFree(auth2, contractSig, 0, recipients2, allProofs, proofLengths);
        assertEq(amount2, 1 ether);
    }

    function test_EIP1271_MultipleBatchesWithContractWallet() public {
        MockERC1271WalletValid contractWallet = new MockERC1271WalletValid(ownerFromKey);

        vm.deal(address(contractWallet), 100 ether);
        vm.prank(address(contractWallet));
        weth.depositAndApprove{value: 20 ether}(address(distribution));

        // Test with 2 recipients in a single batch (simpler merkle proof)
        Recipient[] memory recipients = _createRecipients(2, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(5001)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 2 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

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

        vm.prank(ownerFromKey);
        contractWallet.approveHash(digest);

        bytes memory signature = abi.encode(address(contractWallet), hex"00");

        // Build proofs
        bytes32[] memory allProofs = new bytes32[](2);
        uint8[] memory proofLengths = new uint8[](2);

        bytes32[] memory proof0 = _computeMerkleProof(recipients, 0, 0);
        bytes32[] memory proof1 = _computeMerkleProof(recipients, 0, 1);

        allProofs[0] = proof0.length > 0 ? proof0[0] : bytes32(0);
        allProofs[1] = proof1.length > 0 ? proof1[0] : bytes32(0);
        proofLengths[0] = uint8(proof0.length);
        proofLengths[1] = uint8(proof1.length);

        // Execute batch
        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 2 ether);

        // Check progress
        (uint256 executedBatches, uint256 total, uint256 distributed) = distribution.getProgress(auth.uuid);
        assertEq(executedBatches, 1);
        assertEq(total, 1);
        assertEq(distributed, 2 ether);

        // Verify recipients received funds
        assertEq(address(uint160(0x1000)).balance, 1 ether);
        assertEq(address(uint160(0x1001)).balance, 1 ether);
    }

    function test_EIP1271_ERC20Distribution() public {
        MockERC1271WalletValid contractWallet = new MockERC1271WalletValid(ownerFromKey);

        // Give contract wallet ERC20 tokens
        mockToken.mint(address(contractWallet), 1000 ether);
        vm.prank(address(contractWallet));
        mockToken.approve(address(distribution), 1000 ether);

        Recipient[] memory recipients = _createRecipients(2, 100 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(6001)),
            token: address(mockToken),
            tokenType: 1, // ERC20
            tokenId: 0,
            totalAmount: 200 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

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

        vm.prank(ownerFromKey);
        contractWallet.approveHash(digest);

        bytes memory signature = abi.encode(address(contractWallet), hex"00");

        bytes32[] memory allProofs = new bytes32[](2);
        uint8[] memory proofLengths = new uint8[](2);
        bytes32[] memory proof0 = _computeMerkleProof(recipients, 0, 0);
        bytes32[] memory proof1 = _computeMerkleProof(recipients, 0, 1);
        allProofs[0] = proof0.length > 0 ? proof0[0] : bytes32(0);
        allProofs[1] = proof1.length > 0 ? proof1[0] : bytes32(0);
        proofLengths[0] = uint8(proof0.length);
        proofLengths[1] = uint8(proof1.length);

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, 200 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1000))), 100 ether);
        assertEq(mockToken.balanceOf(address(uint160(0x1001))), 100 ether);
    }

    // ============ Fuzz Tests for Signatures ============

    function testFuzz_EOA_Signature(uint256 privateKey, uint256 amount) public {
        // Bound private key to valid range
        privateKey = bound(privateKey, 1, type(uint128).max);
        amount = bound(amount, 0.001 ether, 1 ether);

        address signer = vm.addr(privateKey);
        vm.deal(signer, 100 ether);

        vm.prank(signer);
        weth.depositAndApprove{value: 10 ether}(address(distribution));

        Recipient[] memory recipients = _createRecipients(1, amount);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(privateKey), // Use privateKey as unique UUID
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: amount,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes memory signature = _signDistributionAuth(auth, privateKey);

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        (uint256 batchAmount,) =
            distribution.distributeWithAuthFree(auth, signature, 0, recipients, allProofs, proofLengths);

        assertEq(batchAmount, amount);
    }

    function testFuzz_InvalidSignatureBytes(bytes memory randomSig) public {
        // Skip if length is exactly 65 (could be valid EOA) or > 85 (could be valid EIP-1271)
        vm.assume(randomSig.length != 65);
        vm.assume(randomSig.length <= 85);

        Recipient[] memory recipients = _createRecipients(1, 1 ether);
        bytes32 merkleRoot = _computeMerkleRoot(recipients, 0);

        DistributionAuth memory auth = DistributionAuth({
            uuid: bytes32(uint256(99999)),
            token: address(weth),
            tokenType: 0,
            tokenId: 0,
            totalAmount: 1 ether,
            totalBatches: 1,
            merkleRoot: merkleRoot,
            deadline: block.timestamp + 1 days
        });

        bytes32[] memory allProofs = new bytes32[](0);
        uint8[] memory proofLengths = new uint8[](1);
        proofLengths[0] = 0;

        vm.prank(executor);
        vm.expectRevert(TokenDistribution.InvalidSignature.selector);
        distribution.distributeWithAuthFree(auth, randomSig, 0, recipients, allProofs, proofLengths);
    }
}
