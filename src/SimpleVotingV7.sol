// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemaphore} from "semaphore/packages/contracts/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "semaphore/packages/contracts/contracts/interfaces/ISemaphoreGroups.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleVotingV7
 * @author Sue
 * @notice 基于 Semaphore 协议的独立树匿名投票系统
 * @dev 教学演示专用 - 展示独立树设计与共享树的对比
 *
 * 核心特性:
 * - 每个用户独立 Merkle Tree (极快证明生成 ~0.5s)
 * - 部分匿名性 (可追踪用户是否投票)
 * - 防双重投票 (Nullifier 机制)
 * - 可升级合约 (UUPS 模式)
 * - 永久提案 (无时间限制)
 *
 * 架构说明:
 * - V7 (独立树): 每个用户独立 Group, 部分匿名, 证明生成极快
 * - 历史 V6 (共享树): 所有用户共享一个 Group, 完全匿名, 证明生成慢
 *
 * 隐私权衡:
 * - V7 失去: 投票者身份完全匿名
 * - V7 保留: ZK 证明保护 (仍需知道 secret)
 * - V7 获得: 极快的证明生成速度
 *
 * 教学价值:
 * - 对比两种隐私级别的设计
 * - 展示隐私 vs 性能的权衡
 * - 理解 ZK 应用的不同场景
 * - 适合学生快速体验投票流程
 */
contract SimpleVotingV7 is Initializable, UUPSUpgradeable {
    // ========== 类型定义 ==========

    /**
     * @dev 提案结构体 (独立树版本)
     * @notice V7: 移除 groupId (不再有共享 Group)
     */
    struct Proposal {
        uint256 id;                 // 提案 ID
        string title;               // 提案标题
        uint256 optionCount;        // 选项数量
        uint256 createdAt;          // 创建时间
        bool isActive;              // 提案状态
    }

    // ========== 状态变量 ==========

    /// @notice 外部 Semaphore 验证器合约
    ISemaphore public semaphore;

    /// @notice 合约所有者
    address private _owner;

    /// @notice 提案计数器
    uint256 public proposalCount;

    /// @notice 提案映射
    mapping(uint256 => Proposal) public proposals;

    /// @notice 选项名称映射 (只存储名称,不含票数)
    mapping(uint256 => mapping(uint256 => string)) public optionNames;

    /// @notice 防双重投票记录
    mapping(uint256 => mapping(uint256 => bool)) public hasVoted;

    /// @notice V7 核心: 用户专属 Group 映射
    /// @dev 提案ID → 用户地址 → 用户的专属 Group ID
    mapping(uint256 => mapping(address => uint256)) public userGroups;

    // ========== 事件 ==========

    /**
     * @notice 提案创建事件 (V7: 不再包含 groupId)
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        string title
    );

    /**
     * @notice 选项添加事件
     */
    event OptionAdded(
        uint256 indexed proposalId,
        uint256 indexed optionId,
        string name
    );

    /**
     * @notice 成员加入事件 (V7: 包含用户专属 groupId)
     */
    event MemberJoined(
        uint256 indexed proposalId,
        uint256 indexed userGroupId,
        uint256 identityCommitment,
        address indexed user
    );

    /**
     * @notice 投票事件 (完全隐私设计: 不包含任何选项信息)
     */
    event VoteCast(uint256 indexed proposalId);

    /**
     * @notice 提案状态变更事件
     */
    event ProposalStatusChanged(uint256 indexed proposalId, bool isActive);

    /**
     * @notice 所有权转移事件
     */
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // ========== 修饰符 ==========

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not the owner");
        _;
    }

    // ========== 初始化 ==========

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约
     * @param _semaphore Semaphore 合约地址
     */
    function initialize(address _semaphore) public initializer {
        require(_semaphore != address(0), "Invalid semaphore address");

        semaphore = ISemaphore(_semaphore);
        _owner = msg.sender;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @notice 初始化合约 V7 (升级用)
     * @param _semaphore 新的 Semaphore 合约地址 (可选,保持不变传 address(0))
     */
    function initializeV7(address _semaphore) public reinitializer(7) {
        if (_semaphore != address(0)) {
            semaphore = ISemaphore(_semaphore);
        }
    }

    // ========== 管理员函数 ==========

    /**
     * @notice 创建提案 (V7: 不创建共享 Group)
     * @param title 提案标题
     * @return proposalId 新创建的提案 ID
     *
     * @dev V7 变化:
     * - 不调用 semaphore.createGroup() (等用户加入时创建独立 Group)
     * - 不存储 groupId
     */
    function createProposal(
        string memory title
    ) external onlyOwner returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");

        proposalCount++;

        // V7: 不创建共享 Group

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.title = title;
        // V7: 移除 p.groupId
        p.createdAt = block.timestamp;
        p.isActive = true;

        emit ProposalCreated(proposalCount, title);

        return proposalCount;
    }

    /**
     * @notice 为提案添加选项
     * @param proposalId 提案 ID
     * @param name 选项名称
     */
    function addOption(
        uint256 proposalId,
        string calldata name
    ) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(bytes(name).length > 0, "Option name cannot be empty");

        p.optionCount++;
        uint256 optionId = p.optionCount;

        optionNames[proposalId][optionId] = name;

        emit OptionAdded(proposalId, optionId, name);
    }

    /**
     * @notice 设置提案状态
     * @param proposalId 提案 ID
     * @param isActive 是否激活
     */
    function setProposalStatus(
        uint256 proposalId,
        bool isActive
    ) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");

        if (isActive) {
            require(p.optionCount > 0, "Cannot activate proposal without options");
        }

        p.isActive = isActive;
        emit ProposalStatusChanged(proposalId, isActive);
    }

    /**
     * @notice 转移所有权
     * @param newOwner 新所有者地址
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // ========== 用户函数 ==========

    /**
     * @notice 用户加入提案 (V7: 创建独立 Group)
     * @param proposalId 提案 ID
     * @param identityCommitment 用户身份承诺
     *
     * @dev V7 核心逻辑:
     * 1. 为该用户创建独立的 Semaphore Group
     * 2. 只将该用户的 IC 加入自己的 Group (树深度 = 1)
     * 3. 存储 userGroups[proposalId][msg.sender] = userGroupId
     * 4. 允许重复加入 (覆盖旧 Group, 教学场景)
     *
     * @dev 安全性:
     * - identityCommitment 由用户自己生成,合约无法获取私钥
     * - ZK 证明仍然保护用户 secret
     * - 但 msg.sender 暴露了用户身份 (V7 接受的代价)
     */
    function joinProposal(
        uint256 proposalId,
        uint256 identityCommitment
    ) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(p.isActive, "Proposal not active");

        // V7: 为该用户创建独立 Group
        uint256 userGroupId = semaphore.createGroup(address(this));

        // 只将该用户的 IC 加入自己的 Group
        semaphore.addMember(userGroupId, identityCommitment);

        // 存储映射 (允许覆盖,教学场景允许重复加入)
        userGroups[proposalId][msg.sender] = userGroupId;

        emit MemberJoined(proposalId, userGroupId, identityCommitment, msg.sender);
    }

    /**
     * @notice 匿名投票 (V7: 使用用户专属 Group)
     * @param proposalId 提案 ID
     * @param semaphoreProof Semaphore 零知识证明
     *
     * @dev V7 极简方案核心逻辑:
     * 1. 直接用 msg.sender 查询用户的 Group ID (O(1))
     * 2. 无需从 proof 推导 groupId (文档原方案已优化)
     * 3. 用用户的专属 Group 验证证明
     * 4. 防止双重投票 (Nullifier 机制)
     *
     * @dev 隐私权衡:
     * - msg.sender 暴露了用户身份
     * - 可以追踪到谁投票了
     * - 但 ZK 证明仍然保护 secret 和选项内容
     * - 这是 V7 接受的代价 (教学场景可接受)
     *
     * @dev 教学重点:
     * - 对比共享树的完全匿名性
     * - 理解独立树带来的性能提升
     * - 学习隐私 vs 性能的权衡
     */
    function vote(
        uint256 proposalId,
        ISemaphore.SemaphoreProof calldata semaphoreProof
    ) external {
        Proposal storage p = proposals[proposalId];

        require(p.isActive, "Proposal not active");
        require(
            !hasVoted[proposalId][semaphoreProof.nullifier],
            "Already voted"
        );

        // V7 核心: 极简 Group ID 查询 (O(1))
        uint256 userGroupId = userGroups[proposalId][msg.sender];
        require(userGroupId != 0, "User not joined this proposal");

        // 验证 ZK 证明 (使用用户的专属 Group)
        // 确认: 1) 投票者的 IC 在自己的 Merkle Tree 中
        //       2) Merkle Root 有效
        //       3) ZK 证明数学正确性
        semaphore.validateProof(userGroupId, semaphoreProof);

        // 标记已投票 (防双重投票)
        hasVoted[proposalId][semaphoreProof.nullifier] = true;

        // 发出投票事件 (不暴露任何选项信息)
        emit VoteCast(proposalId);
    }

    // ========== 查询函数 ==========

    /**
     * @notice 获取提案基本信息 (V7: 不返回 groupId)
     */
    function getProposalInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            string memory title,
            uint256 optionCount,
            uint256 createdAt,
            bool isActive
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.id, p.title, p.optionCount, p.createdAt, p.isActive);
    }

    /**
     * @notice 获取选项名称列表 (不含票数)
     */
    function getOptionNames(
        uint256 proposalId
    ) external view returns (string[] memory names) {
        Proposal storage p = proposals[proposalId];
        names = new string[](p.optionCount);

        for (uint256 i = 1; i <= p.optionCount; i++) {
            names[i - 1] = optionNames[proposalId][i];
        }
    }

    /**
     * @notice 检查 nullifier 是否已投票
     */
    function checkVoted(
        uint256 proposalId,
        uint256 nullifier
    ) external view returns (bool) {
        return hasVoted[proposalId][nullifier];
    }

    /**
     * @notice 获取用户在提案中的 Group ID (V7 新增)
     * @param proposalId 提案 ID
     * @param user 用户地址
     * @return Group ID (0 表示未加入)
     */
    function getUserGroupId(uint256 proposalId, address user)
        external
        view
        returns (uint256)
    {
        return userGroups[proposalId][user];
    }

    /**
     * @notice 获取合约所有者
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice 获取合约版本
     */
    function version() external pure returns (string memory) {
        return "V7.0-IndependentTree";
    }

    // ========== 兼容性查询 ==========

    /**
     * @notice 获取提案标题
     */
    function getProposalTitle(uint256 proposalId)
        external
        view
        returns (string memory)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return p.title;
    }

    /**
     * @notice 获取提案状态
     */
    function getProposalStatus(uint256 proposalId)
        external
        view
        returns (bool)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return p.isActive;
    }

    /**
     * @notice 获取提案截止时间 (永久有效)
     */
    function getProposalDeadline(uint256 proposalId)
        external
        view
        returns (uint256)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return type(uint256).max;
    }

    // ========== Semaphore 便捷查询 (V7: 针对用户专属 Group) ==========

    /**
     * @notice 获取用户 Semaphore Group 的 Merkle Root (V7 新增)
     */
    function getUserMerkleTreeRoot(
        uint256 proposalId,
        address user
    ) external view returns (uint256) {
        uint256 groupId = userGroups[proposalId][user];
        require(groupId != 0, "User not joined");
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId);
    }

    /**
     * @notice 获取用户 Semaphore Group 的 Merkle Tree 深度 (V7 新增)
     */
    function getUserMerkleTreeDepth(
        uint256 proposalId,
        address user
    ) external view returns (uint256) {
        uint256 groupId = userGroups[proposalId][user];
        require(groupId != 0, "User not joined");
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeDepth(groupId);
    }

    /**
     * @notice 获取用户 Semaphore Group 的成员数量 (V7: 应该总是 1)
     */
    function getUserMerkleTreeSize(
        uint256 proposalId,
        address user
    ) external view returns (uint256) {
        uint256 groupId = userGroups[proposalId][user];
        require(groupId != 0, "User not joined");
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeSize(groupId);
    }

    /**
     * @notice 获取用户 Semaphore Group 的管理员 (V7: 应该是本合约)
     */
    function getUserGroupAdmin(
        uint256 proposalId,
        address user
    ) external view returns (address) {
        uint256 groupId = userGroups[proposalId][user];
        require(groupId != 0, "User not joined");
        return ISemaphoreGroups(address(semaphore)).getGroupAdmin(groupId);
    }

    // ========== UUPS 升级授权 ==========

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
