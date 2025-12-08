// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleVotingV2} from "../src/SimpleVotingV2.sol";
import {Semaphore} from "semaphore/packages/contracts/contracts/Semaphore.sol";
import {ISemaphoreVerifier} from "semaphore/packages/contracts/contracts/interfaces/ISemaphoreVerifier.sol";
import {SemaphoreVerifier} from "semaphore/packages/contracts/contracts/base/SemaphoreVerifier.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SimpleVotingV2Test
 * @author Sue
 * @notice 测试套件 - SimpleVotingV2 匿名投票系统
 *
 * @dev 测试覆盖:
 * 1. 初始化测试
 * 2. 提案创建和管理
 * 3. 用户注册 (加入提案)
 * 4. 投票功能 (需要真实 ZK 证明)
 * 5. 查询函数
 * 6. 权限控制
 * 7. 边界条件和错误处理
 */
contract SimpleVotingV2Test is Test {
    // ========== 测试环境 ==========

    SimpleVotingV2 public voting;
    SimpleVotingV2 public implementation;
    SemaphoreVerifier public verifier;
    Semaphore public semaphore;
    ERC1967Proxy public proxy;

    address public owner;
    address public user1;
    address public user2;

    // ========== 设置 ==========

    function setUp() public {
        // 设置测试账户
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // 部署 SemaphoreVerifier
        verifier = new SemaphoreVerifier();

        // 部署 Semaphore
        semaphore = new Semaphore(ISemaphoreVerifier(address(verifier)));

        // 部署 SimpleVotingV2 实现
        implementation = new SimpleVotingV2();

        // 部署代理
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV2.initialize.selector,
            address(semaphore),
            owner
        );
        proxy = new ERC1967Proxy(address(implementation), initData);

        // 通过代理访问
        voting = SimpleVotingV2(address(proxy));
    }

    // ========== 初始化测试 ==========

    function test_Initialize() public view {
        assertEq(voting.owner(), owner, "Owner should be set correctly");
        assertEq(address(voting.semaphore()), address(semaphore), "Semaphore should be set correctly");
        assertEq(voting.proposalCount(), 0, "Proposal count should be 0");
    }

    function testFail_InitializeTwice() public {
        voting.initialize(address(semaphore), owner);
    }

    function testFail_InitializeWithZeroSemaphore() public {
        SimpleVotingV2 newImpl = new SimpleVotingV2();
        bytes memory initData = abi.encodeWithSelector(
            SimpleVotingV2.initialize.selector,
            address(0),
            owner
        );
        new ERC1967Proxy(address(newImpl), initData);
    }

    // ========== 提案创建测试 ==========

    function test_CreateProposal() public {
        string memory title = "Test Proposal";
        uint256 duration = 86400; // 24 hours

        uint256 proposalId = voting.createProposal(title, duration);

        assertEq(proposalId, 1, "Proposal ID should be 1");
        assertEq(voting.proposalCount(), 1, "Proposal count should be 1");
        assertEq(voting.getProposalTitle(proposalId), title, "Proposal title should match");

        uint256 deadline = voting.getProposalDeadline(proposalId);
        assertEq(deadline, block.timestamp + duration, "Deadline should be correct");
    }

    function testFail_CreateProposalEmptyTitle() public {
        voting.createProposal("", 86400);
    }

    function testFail_CreateProposalZeroDuration() public {
        voting.createProposal("Test", 0);
    }

    function test_CreateProposalOnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not owner");
        voting.createProposal("Test", 86400);
    }

    // ========== 选项管理测试 ==========

    function test_AddOption() public {
        uint256 proposalId = voting.createProposal("Test Proposal", 86400);

        voting.addOption(proposalId, "Option A");
        voting.addOption(proposalId, "Option B");
        voting.addOption(proposalId, "Option C");

        SimpleVotingV2.Option[] memory options = voting.getOptions(proposalId);

        assertEq(options.length, 3, "Should have 3 options");
        assertEq(options[0].name, "Option A", "Option 1 name should match");
        assertEq(options[1].name, "Option B", "Option 2 name should match");
        assertEq(options[2].name, "Option C", "Option 3 name should match");
    }

    function testFail_AddOptionNonexistentProposal() public {
        voting.addOption(999, "Option A");
    }

    function testFail_AddOptionEmptyName() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        voting.addOption(proposalId, "");
    }

    function test_AddOptionOnlyOwner() public {
        uint256 proposalId = voting.createProposal("Test", 86400);

        vm.prank(user1);
        vm.expectRevert("Not owner");
        voting.addOption(proposalId, "Option A");
    }

    // ========== 用户注册测试 ==========

    function test_JoinProposal() public {
        uint256 proposalId = voting.createProposal("Test Proposal", 86400);

        // 模拟 identity commitment
        uint256 commitment1 = 123456789;
        uint256 commitment2 = 987654321;

        vm.prank(user1);
        voting.joinProposal(proposalId, commitment1);

        vm.prank(user2);
        voting.joinProposal(proposalId, commitment2);

        // 注意: 无法直接查询群组成员,需要通过事件监听
        // 这里主要验证不会 revert
    }

    function testFail_JoinNonexistentProposal() public {
        voting.joinProposal(999, 123456789);
    }

    function test_JoinExpiredProposal() public {
        uint256 proposalId = voting.createProposal("Test", 100); // 100 seconds

        // 快进时间到过期后
        vm.warp(block.timestamp + 101);

        vm.prank(user1);
        vm.expectRevert("Proposal expired");
        voting.joinProposal(proposalId, 123456789);
    }

    // ========== 投票测试 (基础) ==========

    /**
     * @notice 基础投票测试 (不包含真实 ZK 证明)
     * @dev 真实的投票测试需要:
     * 1. 生成真实的 Semaphore Identity
     * 2. 构建 Merkle Tree
     * 3. 生成 ZK 证明
     * 4. 提交投票
     *
     * 这需要在 JavaScript/TypeScript 测试中完成
     */
    function test_VoteRequiresValidProof() public {
        // 创建提案并添加选项
        uint256 proposalId = voting.createProposal("Test Proposal", 86400);
        voting.addOption(proposalId, "Option A");

        // 用户加入
        uint256 commitment = 123456789;
        vm.prank(user1);
        voting.joinProposal(proposalId, commitment);

        // 尝试投票 (使用无效证明)
        uint256 merkleTreeDepth = 20;
        uint256 merkleTreeRoot = 0;
        uint256 nullifier = 111111111;
        uint256[8] memory proof;

        vm.prank(user1);
        vm.expectRevert(); // 应该因为无效证明而失败
        voting.vote(
            proposalId,
            1, // optionId
            merkleTreeDepth,
            merkleTreeRoot,
            nullifier,
            proof
        );
    }

    // ========== 查询函数测试 ==========

    function test_GetVotes() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        voting.addOption(proposalId, "Option A");

        uint256 votes = voting.getVotes(proposalId, 1);
        assertEq(votes, 0, "Initial vote count should be 0");
    }

    function testFail_GetVotesNonexistentProposal() public view {
        voting.getVotes(999, 1);
    }

    function testFail_GetVotesInvalidOption() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        voting.getVotes(proposalId, 999);
    }

    function test_GetOptions() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        voting.addOption(proposalId, "A");
        voting.addOption(proposalId, "B");

        SimpleVotingV2.Option[] memory options = voting.getOptions(proposalId);

        assertEq(options.length, 2, "Should have 2 options");
        assertEq(options[0].id, 1, "Option 1 ID should be 1");
        assertEq(options[1].id, 2, "Option 2 ID should be 2");
    }

    function test_IsNullifierUsed() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        uint256 nullifier = 123456789;

        bool used = voting.isNullifierUsed(proposalId, nullifier);
        assertEq(used, false, "Nullifier should not be used initially");
    }

    // ========== 边界条件测试 ==========

    function test_MultipleProposals() public {
        voting.createProposal("Proposal 1", 86400);
        voting.createProposal("Proposal 2", 86400);
        voting.createProposal("Proposal 3", 86400);

        assertEq(voting.proposalCount(), 3, "Should have 3 proposals");
    }

    function test_LongProposalTitle() public {
        string memory longTitle = "This is a very long proposal title that should still work correctly even though it is quite lengthy and contains many characters";

        uint256 proposalId = voting.createProposal(longTitle, 86400);

        assertEq(voting.getProposalTitle(proposalId), longTitle, "Long title should be stored correctly");
    }

    // ========== Gas 优化测试 ==========

    function test_GasCreateProposal() public {
        uint256 gasBefore = gasleft();
        voting.createProposal("Test", 86400);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for createProposal:", gasUsed);
        // 通常应该 < 200k gas
    }

    function test_GasAddOption() public {
        uint256 proposalId = voting.createProposal("Test", 86400);

        uint256 gasBefore = gasleft();
        voting.addOption(proposalId, "Option A");
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for addOption:", gasUsed);
        // 通常应该 < 100k gas
    }

    function test_GasJoinProposal() public {
        uint256 proposalId = voting.createProposal("Test", 86400);

        vm.prank(user1);
        uint256 gasBefore = gasleft();
        voting.joinProposal(proposalId, 123456789);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for joinProposal:", gasUsed);
        // 通常应该 < 150k gas (包含 Merkle Tree 更新)
    }

    // ========== 事件测试 ==========

    function test_ProposalCreatedEvent() public {
        vm.expectEmit(true, false, false, true);
        emit SimpleVotingV2.ProposalCreated(1, "Test", 1, block.timestamp + 86400);

        voting.createProposal("Test", 86400);
    }

    function test_OptionAddedEvent() public {
        uint256 proposalId = voting.createProposal("Test", 86400);

        vm.expectEmit(true, false, false, true);
        emit SimpleVotingV2.OptionAdded(proposalId, 1, "Option A");

        voting.addOption(proposalId, "Option A");
    }

    function test_MemberJoinedEvent() public {
        uint256 proposalId = voting.createProposal("Test", 86400);
        uint256 commitment = 123456789;

        vm.expectEmit(true, true, false, true);
        emit SimpleVotingV2.MemberJoined(proposalId, proposalId, commitment);

        vm.prank(user1);
        voting.joinProposal(proposalId, commitment);
    }
}
