// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TokenFactory, SimpleToken} from "../src/tools/TokenFactory.sol";
import {TokenInfo} from "../src/interfaces/ITokenFactory.sol";
import {BiuBiuPremium} from "../src/core/BiuBiuPremium.sol";

contract TokenFactoryTest is Test {
    TokenFactory public factory;
    BiuBiuPremium public premium;

    address public vault = 0x46AFD0cA864D4E5235DA38a71687163Dc83828cE;
    address public alice = address(0x1);
    address public bob = address(0x2);

    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint8 decimals,
        uint256 initialSupply,
        bool mintable,
        uint8 usageType
    );

    function setUp() public {
        premium = new BiuBiuPremium(vault);
        factory = new TokenFactory(address(premium));
    }

    // ========== Token Creation Tests ==========

    function test_CreateTokenBasic() public {
        vm.startPrank(alice);

        address tokenAddress = factory.createTokenFree("My Token", "MTK", 18, 1000 ether, false);

        SimpleToken token = SimpleToken(tokenAddress);

        assertEq(token.name(), "My Token");
        assertEq(token.symbol(), "MTK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1000 ether);
        assertEq(token.balanceOf(alice), 1000 ether);
        assertEq(token.owner(), alice);
        assertEq(token.mintable(), false);

        vm.stopPrank();
    }

    function test_CreateTokenWithMintable() public {
        vm.startPrank(alice);

        address tokenAddress = factory.createTokenFree("Mintable Token", "MINT", 18, 1000 ether, true);

        SimpleToken token = SimpleToken(tokenAddress);

        assertEq(token.mintable(), true);

        // Alice should be able to mint more tokens
        token.mint(alice, 500 ether);
        assertEq(token.totalSupply(), 1500 ether);
        assertEq(token.balanceOf(alice), 1500 ether);

        vm.stopPrank();
    }

    function test_CreateTokenZeroSupply() public {
        vm.startPrank(alice);

        address tokenAddress = factory.createTokenFree("Zero Token", "ZERO", 18, 0, true);

        SimpleToken token = SimpleToken(tokenAddress);

        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);

        // But can mint later
        token.mint(alice, 100 ether);
        assertEq(token.totalSupply(), 100 ether);

        vm.stopPrank();
    }

    function test_CreateTokenCustomDecimals() public {
        vm.startPrank(alice);

        address tokenAddress = factory.createTokenFree("USDC Clone", "USDC", 6, 1000000 * 1e6, false);

        SimpleToken token = SimpleToken(tokenAddress);

        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 1000000 * 1e6);

        vm.stopPrank();
    }

    function test_CreateTokenEmitsEvent() public {
        vm.startPrank(alice);

        vm.expectEmit(false, true, false, false);
        emit TokenCreated(address(0), alice, "Test", "TST", 18, 1000 ether, true, 0);

        factory.createTokenFree("Test", "TST", 18, 1000 ether, true);

        vm.stopPrank();
    }

    function test_CreateTokenEmptyNameReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("TokenFactory: name cannot be empty");
        factory.createTokenFree("", "TST", 18, 1000 ether, false);

        vm.stopPrank();
    }

    function test_CreateTokenEmptySymbolReverts() public {
        vm.startPrank(alice);

        vm.expectRevert("TokenFactory: symbol cannot be empty");
        factory.createTokenFree("Test", "", 18, 1000 ether, false);

        vm.stopPrank();
    }

    function test_CreateTokenSameNameAllowedDifferentCreators() public {
        // Alice creates "My Token"
        vm.prank(alice);
        address token1 = factory.createTokenFree("My Token", "MTK1", 18, 1000 ether, false);

        // Bob can also create "My Token" (different creator = different salt)
        vm.prank(bob);
        address token2 = factory.createTokenFree("My Token", "MTK2", 18, 2000 ether, false);

        // Both should exist
        assertFalse(token1 == token2);
        assertEq(SimpleToken(token1).name(), "My Token");
        assertEq(SimpleToken(token2).name(), "My Token");
        assertEq(SimpleToken(token1).owner(), alice);
        assertEq(SimpleToken(token2).owner(), bob);
    }

    function test_CreateTokenSameSymbolAllowed() public {
        vm.prank(alice);
        address token1 = factory.createTokenFree("Token One", "MTK", 18, 1000 ether, false);

        // Should allow creating another token with same symbol but different name
        vm.prank(bob);
        address token2 = factory.createTokenFree("Token Two", "MTK", 18, 2000 ether, false);

        // Both should exist with same symbol
        assertFalse(token1 == token2);
        assertEq(SimpleToken(token1).symbol(), "MTK");
        assertEq(SimpleToken(token2).symbol(), "MTK");
        assertEq(SimpleToken(token1).name(), "Token One");
        assertEq(SimpleToken(token2).name(), "Token Two");
    }

    function test_SameCreatorSameParamsReverts() public {
        vm.startPrank(alice);

        // Alice creates "My Token"
        factory.createTokenFree("My Token", "MTK", 18, 1000 ether, false);

        // Alice tries to create identical token - should revert (same salt + same bytecode)
        vm.expectRevert();
        factory.createTokenFree("My Token", "MTK", 18, 1000 ether, false);

        vm.stopPrank();
    }

    function test_SameCreatorSameNameDifferentParamsAllowed() public {
        vm.startPrank(alice);

        // Alice creates "My Token" with MTK
        address token1 = factory.createTokenFree("My Token", "MTK", 18, 1000 ether, false);

        // Alice can create "My Token" with different params (different bytecode)
        address token2 = factory.createTokenFree("My Token", "MTK2", 18, 2000 ether, true);

        // Both should exist
        assertFalse(token1 == token2);
        assertEq(SimpleToken(token1).symbol(), "MTK");
        assertEq(SimpleToken(token2).symbol(), "MTK2");

        vm.stopPrank();
    }

    function test_PredictTokenAddress() public {
        // Predict address before deployment
        address predicted = factory.predictTokenAddress("My Token", "MTK", 18, 1000 ether, false, alice);

        // Deploy token
        vm.prank(alice);
        address actual = factory.createTokenFree("My Token", "MTK", 18, 1000 ether, false);

        // Should match
        assertEq(predicted, actual);
    }

    function test_CREATE2SameAddressAcrossChains() public {
        // Same name should produce same address (in theory, across chains)
        address predicted1 = factory.predictTokenAddress("Bitcoin", "BTC", 18, 1000 ether, false, alice);
        address predicted2 = factory.predictTokenAddress("Bitcoin", "BTC", 18, 1000 ether, false, alice);

        assertEq(predicted1, predicted2);

        // Different name should produce different address
        address predicted3 = factory.predictTokenAddress("Ethereum", "ETH", 18, 1000 ether, false, alice);
        assertFalse(predicted1 == predicted3);
    }

    // ========== Tracking Tests ==========

    function test_TrackAllTokens() public {
        vm.prank(alice);
        address token1 = factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);

        vm.prank(bob);
        address token2 = factory.createTokenFree("Token2", "TK2", 18, 2000 ether, false);

        assertEq(factory.allTokensLength(), 2);

        address[] memory allTokens = factory.getAllTokens();
        assertEq(allTokens.length, 2);
        assertEq(allTokens[0], token1);
        assertEq(allTokens[1], token2);
    }

    function test_TrackUserTokens() public {
        vm.startPrank(alice);

        address token1 = factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);
        address token2 = factory.createTokenFree("Token2", "TK2", 18, 2000 ether, false);

        vm.stopPrank();

        vm.prank(bob);
        address token3 = factory.createTokenFree("Token3", "TK3", 18, 3000 ether, false);

        // Check alice's tokens
        assertEq(factory.userTokensLength(alice), 2);
        address[] memory aliceTokens = factory.getUserTokens(alice);
        assertEq(aliceTokens.length, 2);
        assertEq(aliceTokens[0], token1);
        assertEq(aliceTokens[1], token2);

        // Check bob's tokens
        assertEq(factory.userTokensLength(bob), 1);
        address[] memory bobTokens = factory.getUserTokens(bob);
        assertEq(bobTokens.length, 1);
        assertEq(bobTokens[0], token3);
    }

    // ========== SimpleToken Functionality Tests ==========

    function test_TokenTransfer() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("Test", "TST", 18, 1000 ether, false);

        SimpleToken token = SimpleToken(tokenAddress);

        vm.startPrank(alice);

        token.transfer(bob, 300 ether);

        assertEq(token.balanceOf(alice), 700 ether);
        assertEq(token.balanceOf(bob), 300 ether);

        vm.stopPrank();
    }

    function test_TokenApproveAndTransferFrom() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("Test", "TST", 18, 1000 ether, false);

        SimpleToken token = SimpleToken(tokenAddress);

        vm.prank(alice);
        token.approve(bob, 500 ether);

        vm.startPrank(bob);

        token.transferFrom(alice, bob, 200 ether);

        assertEq(token.balanceOf(alice), 800 ether);
        assertEq(token.balanceOf(bob), 200 ether);
        assertEq(token.allowance(alice, bob), 300 ether);

        vm.stopPrank();
    }

    function test_MintOnlyOwner() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("Test", "TST", 18, 1000 ether, true);

        SimpleToken token = SimpleToken(tokenAddress);

        // Bob tries to mint - should fail
        vm.startPrank(bob);
        vm.expectRevert("SimpleToken: caller is not the owner");
        token.mint(bob, 100 ether);
        vm.stopPrank();

        // Alice can mint
        vm.prank(alice);
        token.mint(bob, 100 ether);

        assertEq(token.balanceOf(bob), 100 ether);
        assertEq(token.totalSupply(), 1100 ether);
    }

    function test_MintNotMintableReverts() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("Test", "TST", 18, 1000 ether, false);

        SimpleToken token = SimpleToken(tokenAddress);

        vm.startPrank(alice);
        vm.expectRevert("SimpleToken: minting is disabled");
        token.mint(alice, 100 ether);
        vm.stopPrank();
    }

    function test_MintZeroAmountReverts() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("Test", "TST", 18, 1000 ether, true);

        SimpleToken token = SimpleToken(tokenAddress);

        vm.startPrank(alice);
        vm.expectRevert("SimpleToken: mint amount must be greater than 0");
        token.mint(alice, 0);
        vm.stopPrank();
    }

    // ========== Integration Tests ==========

    function test_MultipleUsersCreateTokens() public {
        // Alice creates 2 tokens
        vm.startPrank(alice);
        factory.createTokenFree("Alice Token 1", "AT1", 18, 1000 ether, false);
        factory.createTokenFree("Alice Token 2", "AT2", 6, 1000000 * 1e6, true);
        vm.stopPrank();

        // Bob creates 1 token
        vm.prank(bob);
        factory.createTokenFree("Bob Token", "BT", 18, 5000 ether, true);

        // Check totals
        assertEq(factory.allTokensLength(), 3);
        assertEq(factory.userTokensLength(alice), 2);
        assertEq(factory.userTokensLength(bob), 1);
    }

    // ========== Pagination Tests ==========

    function test_GetUserTokensPaginated() public {
        // Alice creates 5 tokens
        vm.startPrank(alice);
        address token1 = factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);
        address token2 = factory.createTokenFree("Token2", "TK2", 18, 1000 ether, false);
        address token3 = factory.createTokenFree("Token3", "TK3", 18, 1000 ether, false);
        address token4 = factory.createTokenFree("Token4", "TK4", 18, 1000 ether, false);
        address token5 = factory.createTokenFree("Token5", "TK5", 18, 1000 ether, false);
        vm.stopPrank();

        // Get first 2 tokens (offset=0, limit=2)
        (address[] memory tokens, uint256 total) = factory.getUserTokensPaginated(alice, 0, 2);
        assertEq(total, 5);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);

        // Get next 2 tokens (offset=2, limit=2)
        (tokens, total) = factory.getUserTokensPaginated(alice, 2, 2);
        assertEq(total, 5);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token3);
        assertEq(tokens[1], token4);

        // Get last token (offset=4, limit=2)
        (tokens, total) = factory.getUserTokensPaginated(alice, 4, 2);
        assertEq(total, 5);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token5);
    }

    function test_GetUserTokensPaginatedOffsetTooLarge() public {
        vm.prank(alice);
        factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);

        // Offset beyond total
        (address[] memory tokens, uint256 total) = factory.getUserTokensPaginated(alice, 10, 5);
        assertEq(total, 1);
        assertEq(tokens.length, 0);
    }

    function test_GetUserTokensPaginatedEmptyUser() public {
        // User with no tokens
        (address[] memory tokens, uint256 total) = factory.getUserTokensPaginated(bob, 0, 10);
        assertEq(total, 0);
        assertEq(tokens.length, 0);
    }

    function test_GetAllTokensPaginated() public {
        // Create multiple tokens from different users
        vm.prank(alice);
        address token1 = factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);

        vm.prank(bob);
        address token2 = factory.createTokenFree("Token2", "TK2", 18, 1000 ether, false);

        vm.prank(alice);
        address token3 = factory.createTokenFree("Token3", "TK3", 18, 1000 ether, false);

        // Get first 2 tokens
        (address[] memory tokens, uint256 total) = factory.getAllTokensPaginated(0, 2);
        assertEq(total, 3);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);

        // Get last token
        (tokens, total) = factory.getAllTokensPaginated(2, 10);
        assertEq(total, 3);
        assertEq(tokens.length, 1);
        assertEq(tokens[0], token3);
    }

    function test_GetAllTokensPaginatedLargeLimit() public {
        vm.startPrank(alice);
        address token1 = factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);
        address token2 = factory.createTokenFree("Token2", "TK2", 18, 1000 ether, false);
        vm.stopPrank();

        // Limit larger than total
        (address[] memory tokens, uint256 total) = factory.getAllTokensPaginated(0, 100);
        assertEq(total, 2);
        assertEq(tokens.length, 2);
        assertEq(tokens[0], token1);
        assertEq(tokens[1], token2);
    }

    // ========== Token Info Tests ==========

    function test_GetTokenInfo() public {
        vm.prank(alice);
        address tokenAddress = factory.createTokenFree("My Token", "MTK", 18, 1000 ether, true);

        TokenInfo memory info = factory.getTokenInfo(tokenAddress);

        assertEq(info.tokenAddress, tokenAddress);
        assertEq(info.name, "My Token");
        assertEq(info.symbol, "MTK");
        assertEq(info.decimals, 18);
        assertEq(info.totalSupply, 1000 ether);
        assertEq(info.mintable, true);
        assertEq(info.owner, alice);
    }

    function test_GetUserTokensInfoPaginated() public {
        // Alice creates 3 tokens
        vm.startPrank(alice);
        factory.createTokenFree("Token1", "TK1", 18, 1000 ether, false);
        factory.createTokenFree("Token2", "TK2", 6, 2000000, true);
        factory.createTokenFree("Token3", "TK3", 9, 500 ether, false);
        vm.stopPrank();

        // Get first 2 tokens with info
        (TokenInfo[] memory tokenInfos, uint256 total) = factory.getUserTokensInfoPaginated(alice, 0, 2);

        assertEq(total, 3);
        assertEq(tokenInfos.length, 2);

        // Check first token
        assertEq(tokenInfos[0].name, "Token1");
        assertEq(tokenInfos[0].symbol, "TK1");
        assertEq(tokenInfos[0].decimals, 18);
        assertEq(tokenInfos[0].totalSupply, 1000 ether);
        assertEq(tokenInfos[0].mintable, false);
        assertEq(tokenInfos[0].owner, alice);

        // Check second token
        assertEq(tokenInfos[1].name, "Token2");
        assertEq(tokenInfos[1].symbol, "TK2");
        assertEq(tokenInfos[1].decimals, 6);
        assertEq(tokenInfos[1].totalSupply, 2000000);
        assertEq(tokenInfos[1].mintable, true);
        assertEq(tokenInfos[1].owner, alice);

        // Get last token
        (tokenInfos, total) = factory.getUserTokensInfoPaginated(alice, 2, 10);
        assertEq(total, 3);
        assertEq(tokenInfos.length, 1);
        assertEq(tokenInfos[0].name, "Token3");
        assertEq(tokenInfos[0].symbol, "TK3");
    }

    function test_GetAllTokensInfoPaginated() public {
        // Multiple users create tokens
        vm.prank(alice);
        factory.createTokenFree("Alice Token", "AT", 18, 1000 ether, false);

        vm.prank(bob);
        factory.createTokenFree("Bob Token", "BT", 6, 500000, true);

        // Get all tokens with info
        (TokenInfo[] memory tokenInfos, uint256 total) = factory.getAllTokensInfoPaginated(0, 10);

        assertEq(total, 2);
        assertEq(tokenInfos.length, 2);

        // Check alice's token
        assertEq(tokenInfos[0].name, "Alice Token");
        assertEq(tokenInfos[0].owner, alice);

        // Check bob's token
        assertEq(tokenInfos[1].name, "Bob Token");
        assertEq(tokenInfos[1].owner, bob);
    }

    function test_GetUserTokensInfoPaginatedEmpty() public {
        (TokenInfo[] memory tokenInfos, uint256 total) = factory.getUserTokensInfoPaginated(alice, 0, 10);

        assertEq(total, 0);
        assertEq(tokenInfos.length, 0);
    }

    // ========== Fuzz Tests ==========

    function testFuzz_CreateToken(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint96 initialSupply,
        bool mintable
    ) public {
        vm.assume(bytes(name).length > 0 && bytes(name).length < 100);
        vm.assume(bytes(symbol).length > 0 && bytes(symbol).length < 20);
        vm.assume(decimals <= 18);

        vm.prank(alice);
        address tokenAddress = factory.createTokenFree(name, symbol, decimals, initialSupply, mintable);

        SimpleToken token = SimpleToken(tokenAddress);

        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
        assertEq(token.decimals(), decimals);
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.balanceOf(alice), initialSupply);
        assertEq(token.mintable(), mintable);
    }
}
