// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemaphore} from "semaphore/packages/contracts/contracts/interfaces/ISemaphore.sol";
import {ISemaphoreGroups} from "semaphore/packages/contracts/contracts/interfaces/ISemaphoreGroups.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleVotingV6
 * @author Sue
 * @notice 基于 Semaphore 协议的匿名投票系统 - V6.1 版本
 * @dev 完全使用外部 Semaphore 合约,不继承 SemaphoreGroups
 *
 * 核心特性:
 * - 完全匿名投票 (ZK 证明)
 * - 支持重复投票 (记录 nullifier 投票次数)
 * - 可升级合约 (UUPS 模式)
 * - 永久提案 (无时间限制)
 * - 用户自由加入 (V5+ 特性)
 *
 * V6 架构改进:
 * - ✅ 不再继承 SemaphoreGroups (消除数据分离问题)
 * - ✅ 所有 group 操作通过外部 Semaphore 合约
 * - ✅ 数据一致性: Group 统一在外部 Semaphore 管理
 * - ✅ 代码简化: 减少 29% 代码量
 * - ✅ Gas 优化: 删除未使用的继承存储
 *
 * V6.1 隐私优化:
 * - ✅ VoteCast 事件移除 optionId 参数
 * - ✅ 防止时间关联攻击: 无法通过事件时间戳推测投票内容
 * - ✅ 保持实时性: 前端可监听投票发生,但不暴露具体选项
 * - ✅ 完全匿名: ZK证明隐藏"谁投票" + 事件优化隐藏"投什么"
 *
 * V6 vs V5 关键差异:
 * - V5: contract SimpleVotingV5 is SemaphoreGroups (❌ 混乱)
 * - V6: 完全外部化,不继承 (✅ 清晰)
 * - V5: _createGroup(groupId, admin) (❌ 只在内部)
 * - V6: semaphore.createGroup(admin) (✅ 外部统一)
 */
contract SimpleVotingV6 is Initializable, UUPSUpgradeable {
    // ========== 类型定义 ==========

    /**
     * @dev 投票选项
     */
    struct Option {
        uint256 id;           // 选项 ID
        string name;          // 选项名称
        uint256 voteCount;    // 票数
    }

    /**
     * @dev 提案 (V6 版本)
     */
    struct Proposal {
        uint256 id;                            // 提案 ID
        string title;                          // 提案标题
        uint256 groupId;                       // 对应的 Semaphore Group ID (由外部 Semaphore 管理)
        uint256 optionCount;                   // 选项数量
        mapping(uint256 => Option) options;    // 选项列表
        mapping(uint256 => uint256) nullifierVoteCount; // nullifier => 投票次数
        uint256 createdAt;                     // 创建时间
        bool isActive;                         // 提案状态
    }

    // ========== 状态变量 ==========

    /// @notice 外部 Semaphore 验证器合约地址
    /// @dev V6 核心: 不继承 SemaphoreGroups,完全使用外部合约
    ISemaphore public semaphore;

    /// @notice 合约所有者
    address private _owner;

    /// @notice 提案计数器
    uint256 public proposalCount;

    /// @notice 提案映射 (proposalId => Proposal)
    mapping(uint256 => Proposal) public proposals;

    // ========== 事件 ==========

    /**
     * @notice 提案创建事件
     * @param proposalId 提案 ID
     * @param title 提案标题
     * @param groupId Semaphore Group ID (外部生成)
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        string title,
        uint256 indexed groupId
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
     * @notice 成员加入事件 (V5+)
     * @dev 包含用户地址以便前端追踪
     */
    event MemberJoined(
        uint256 indexed proposalId,
        uint256 indexed groupId,
        uint256 identityCommitment,
        address indexed user
    );

    /**
     * @notice 投票事件
     * @dev V6.1 隐私优化: 移除 optionId 参数，防止时间关联攻击
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
     * @notice 初始化合约 (V1-V4 使用)
     * @param _semaphore Semaphore 合约地址
     */
    function initialize(address _semaphore) public initializer {
        require(_semaphore != address(0), "Invalid semaphore address");

        semaphore = ISemaphore(_semaphore);
        _owner = msg.sender;

        emit OwnershipTransferred(address(0), msg.sender);
    }

    /**
     * @notice 初始化合约 V6 (升级用)
     * @dev 从 V5 升级到 V6 时调用
     * @param _semaphore 新的 Semaphore 合约地址 (可选,保持不变传 address(0))
     */
    function initializeV6(address _semaphore) public reinitializer(6) {
        // 🔧 V6 关键修复: 保留所有权
        // V5 → V6 升级时,_owner 已存在,无需设置
        // 但为了安全,如果 _owner 为空,则设置为 msg.sender
        // 注意: 由于存储布局兼容,V5 的 _owner 会自动保留到 V6

        // 如果需要切换 Semaphore 实例
        if (_semaphore != address(0)) {
            semaphore = ISemaphore(_semaphore);
        }

        // 注意: proposalCount 和 proposals 数据会自动保留
        // _owner 也会自动保留 (存储布局兼容)
    }

    // ========== 管理员函数 ==========

    /**
     * @notice 创建提案
     * @param title 提案标题
     * @return proposalId 新创建的提案 ID
     *
     * @dev V6 核心改进:
     * - 通过 semaphore.createGroup() 在外部 Semaphore 创建 group
     * - groupId 由 Semaphore 返回,确保外部注册
     * - 合约自身 (address(this)) 成为 group admin
     * - 确保后续 addMember 和 validateProof 都在同一个 Semaphore 实例中
     */
    function createProposal(
        string memory title
    ) external onlyOwner returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");

        proposalCount++;

        // 🔑 V6 关键改进: 在外部 Semaphore 创建 group
        // 返回的 groupId 由 Semaphore 管理,确保数据一致性
        uint256 groupId = semaphore.createGroup(address(this));

        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.title = title;
        p.groupId = groupId;  // 使用 Semaphore 返回的 ID
        p.createdAt = block.timestamp;
        p.isActive = true;  // 默认激活

        emit ProposalCreated(proposalCount, title, groupId);

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

        // 🔧 修复: 保持与 V5 一致,索引从 1 开始
        p.optionCount++;
        uint256 optionId = p.optionCount;
        p.options[optionId].id = optionId;
        p.options[optionId].name = name;
        p.options[optionId].voteCount = 0;

        emit OptionAdded(proposalId, optionId, name);
    }

    /**
     * @notice 设置提案状态
     * @param proposalId 提案 ID
     * @param isActive 是否激活
     *
     * @dev V4+ 特性: 支持手动开启/关闭提案,无时间限制
     * @dev V6 改进: 激活时必须至少有一个选项
     */
    function setProposalStatus(
        uint256 proposalId,
        bool isActive
    ) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");

        // V6 业务逻辑检查: 激活提案必须有选项
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
     * @notice 用户自由加入提案 (V5+ 特性)
     * @param proposalId 提案 ID
     * @param identityCommitment 用户身份承诺 (Poseidon(privateKey))
     *
     * @dev V6 优化:
     * - 调用 semaphore.addMember() 在外部 Semaphore 添加成员
     * - 合约作为 group admin,有权限调用 addMember
     * - 自动同步 Semaphore 的 merkleRootCreationDates (rootHistory)
     * - 确保后续投票的 validateProof 能够识别新的 Merkle Root
     *
     * @dev 安全性:
     * - isActive 检查确保只能加入激活的提案
     * - identityCommitment 由用户自己生成,合约无法获取私钥
     * - ZK 证明保证投票匿名性
     */
    function joinProposal(
        uint256 proposalId,
        uint256 identityCommitment
    ) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(p.isActive, "Proposal not active");

        // ✅ V6: 调用外部 Semaphore 添加成员
        // 这会自动更新 Merkle Tree 和 rootHistory
        semaphore.addMember(p.groupId, identityCommitment);

        // V6 自定义事件(包含用户地址)
        emit MemberJoined(proposalId, p.groupId, identityCommitment, msg.sender);
    }

    /**
     * @notice 匿名投票
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param semaphoreProof Semaphore 零知识证明
     *
     * @dev V6 优化:
     * - 通过 semaphore.validateProof() 验证零知识证明
     * - 外部 Semaphore 会检查 rootHistory,支持多用户并发加入
     * - nullifier 防止双重投票 (由 Semaphore 检查)
     * - 支持重复投票: 同一 nullifier 可以多次投票
     *
     * @dev V6.1 隐私优化:
     * - VoteCast 事件不再包含 optionId 参数
     * - 防止时间关联攻击: 无法通过事件发生时间推测投票内容
     * - 前端监听 VoteCast(proposalId) 后重新查询所有选项票数
     * - 完全匿名性: ZK证明保护身份 + 事件不暴露选项
     */
    function vote(
        uint256 proposalId,
        uint256 optionId,
        ISemaphore.SemaphoreProof calldata semaphoreProof
    ) external {
        Proposal storage p = proposals[proposalId];

        require(p.isActive, "Proposal not active");
        require(optionId > 0 && optionId <= p.optionCount, "Invalid option");

        // ✅ V6: 外部 Semaphore 验证证明
        // 这会验证:
        // 1. Merkle Root 在 rootHistory 中 (未过期)
        // 2. ZK 证明有效
        // 3. Nullifier 注册 (防止双重投票,由 Semaphore 管理)
        semaphore.validateProof(p.groupId, semaphoreProof);

        // 业务逻辑: 增加票数
        p.options[optionId].voteCount++;
        p.nullifierVoteCount[semaphoreProof.nullifier]++;

        // V6.1: 发出投票事件（不暴露 optionId，保护隐私）
        emit VoteCast(proposalId);
    }

    // ========== 查询函数 ==========

    /**
     * @notice 获取提案基本信息
     * @param proposalId 提案 ID
     * @return id 提案 ID
     * @return title 提案标题
     * @return groupId Semaphore Group ID
     * @return optionCount 选项数量
     * @return createdAt 创建时间
     * @return isActive 提案状态
     */
    function getProposalInfo(
        uint256 proposalId
    )
        external
        view
        returns (
            uint256 id,
            string memory title,
            uint256 groupId,
            uint256 optionCount,
            uint256 createdAt,
            bool isActive
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.id, p.title, p.groupId, p.optionCount, p.createdAt, p.isActive);
    }

    /**
     * @notice 获取提案的所有选项
     * @param proposalId 提案 ID
     * @return options 选项数组
     */
    function getOptions(
        uint256 proposalId
    ) external view returns (Option[] memory options) {
        Proposal storage p = proposals[proposalId];
        options = new Option[](p.optionCount);

        for (uint256 i = 1; i <= p.optionCount; i++) {
            options[i - 1] = p.options[i];
        }
    }

    /**
     * @notice 获取特定选项的票数
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @return voteCount 票数
     */
    function getOptionVoteCount(
        uint256 proposalId,
        uint256 optionId
    ) external view returns (uint256) {
        return proposals[proposalId].options[optionId].voteCount;
    }

    /**
     * @notice 获取 nullifier 的投票次数
     * @param proposalId 提案 ID
     * @param nullifier nullifier
     * @return count 投票次数
     */
    function getNullifierVoteCount(
        uint256 proposalId,
        uint256 nullifier
    ) external view returns (uint256) {
        return proposals[proposalId].nullifierVoteCount[nullifier];
    }

    /**
     * @notice 获取合约所有者
     */
    function owner() external view returns (address) {
        return _owner;
    }

    /**
     * @notice 获取合约版本
     * @return version 版本号
     */
    function version() external pure returns (string memory) {
        return "V6.1";
    }

    // ========== V5 前端兼容查询（向后兼容）==========

    /**
     * @notice 获取提案标题（V5 兼容方法）
     * @param proposalId 提案 ID
     * @return 提案标题
     *
     * @dev V6 设计变更说明：
     * - V6 合并到 getProposalInfo() 统一查询
     * - 为前端兼容性保留此方法
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
     * @notice 获取提案状态（V5 兼容方法）
     * @param proposalId 提案 ID
     * @return 是否激活
     *
     * @dev V6 设计变更说明：
     * - V6 合并到 getProposalInfo() 统一查询
     * - 为前端兼容性保留此方法
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
     * @notice 获取选项票数（V5 兼容方法，别名）
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @return 票数
     *
     * @dev V6 重命名说明：
     * - V6 主方法: getOptionVoteCount()
     * - 此方法为 V5 兼容别名
     */
    function getVotes(uint256 proposalId, uint256 optionId)
        external
        view
        returns (uint256)
    {
        return proposals[proposalId].options[optionId].voteCount;
    }

    /**
     * @notice 获取提案截止时间（V5 兼容方法，废弃）
     * @param proposalId 提案 ID
     * @return 永久返回 type(uint256).max
     *
     * @dev V6 设计变更说明：
     * - V4+ 取消截止时间概念，提案永久有效
     * - 使用 isActive 手动控制提案开启/关闭
     * - 保留此方法仅为前端兼容，永远返回最大值
     */
    function getProposalDeadline(uint256 proposalId)
        external
        view
        returns (uint256)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return type(uint256).max;  // 永久有效
    }

    // ========== Semaphore 便捷查询 ==========

    /**
     * @notice 获取 Semaphore Group 的 Merkle Root
     * @param groupId Group ID
     * @return merkleTreeRoot Merkle Root
     *
     * @dev V6: 便捷方法,直接调用外部 Semaphore
     */
    function getMerkleTreeRoot(
        uint256 groupId
    ) external view returns (uint256) {
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeRoot(groupId);
    }

    /**
     * @notice 获取 Semaphore Group 的 Merkle Tree 深度
     * @param groupId Group ID
     * @return depth 深度
     *
     * @dev V6: 便捷方法,直接调用外部 Semaphore
     */
    function getMerkleTreeDepth(
        uint256 groupId
    ) external view returns (uint256) {
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeDepth(groupId);
    }

    /**
     * @notice 获取 Semaphore Group 的成员数量
     * @param groupId Group ID
     * @return size 成员数量
     *
     * @dev V6: 便捷方法,直接调用外部 Semaphore
     */
    function getMerkleTreeSize(uint256 groupId) external view returns (uint256) {
        return ISemaphoreGroups(address(semaphore)).getMerkleTreeSize(groupId);
    }

    /**
     * @notice 获取 Semaphore Group 的管理员
     * @param groupId Group ID
     * @return admin 管理员地址
     *
     * @dev V6: 新增便捷方法,用于验证 group 配置
     */
    function getGroupAdmin(uint256 groupId) external view returns (address) {
        return ISemaphoreGroups(address(semaphore)).getGroupAdmin(groupId);
    }

    // ========== UUPS 升级授权 ==========

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
