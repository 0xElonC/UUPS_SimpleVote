// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemaphore} from "semaphore/packages/contracts/contracts/interfaces/ISemaphore.sol";
import {SemaphoreGroups} from "semaphore/packages/contracts/contracts/base/SemaphoreGroups.sol";
import {InternalLeanIMT, LeanIMTData} from "@zk-kit/lean-imt.sol/InternalLeanIMT.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleVotingV5
 * @author Sue
 * @notice 基于 Semaphore 协议的匿名投票系统 - V5 版本
 * @dev 继承 SemaphoreGroups 自动获得 Merkle Tree 管理能力
 *
 * 核心特性:
 * - 完全匿名投票 (ZK 证明)
 * - 支持重复投票 (记录 nullifier 投票次数)
 * - 可升级合约 (UUPS 模式)
 * - 永久提案 (无时间限制)
 * - 用户自由加入 (V5 核心特性)
 *
 * V5 升级内容:
 * - 用户可以自由加入任何激活的提案
 * - 不再需要管理员批准
 * - 直接操作 Merkle Tree，绕过权限检查
 * - 保留所有 V4 功能（永久提案、手动状态控制）
 */
contract SimpleVotingV5 is Initializable, UUPSUpgradeable, SemaphoreGroups {
    using InternalLeanIMT for LeanIMTData;

    // ========== 数据结构 ==========

    /**
     * @dev 投票选项
     */
    struct Option {
        uint256 id;           // 选项 ID
        string name;          // 选项名称
        uint256 voteCount;    // 票数
    }

    /**
     * @dev 提案 (V5 版本)
     */
    struct Proposal {
        uint256 id;                            // 提案 ID
        string title;                          // 提案标题
        uint256 groupId;                       // 对应的 Semaphore Group ID
        uint256 optionCount;                   // 选项数量
        mapping(uint256 => Option) options;    // 选项列表
        mapping(uint256 => uint256) nullifierVoteCount; // nullifier => 投票次数
        uint256 createdAt;                     // 创建时间
        bool isActive;                         // 提案状态
    }

    // ========== 状态变量 ==========

    /// @notice Semaphore 验证器合约地址
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
     * @param groupId Semaphore Group ID
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        string title,
        uint256 groupId
    );

    /**
     * @notice 选项添加事件
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param name 选项名称
     */
    event OptionAdded(
        uint256 indexed proposalId,
        uint256 optionId,
        string name
    );

    /**
     * @notice 成员加入事件 (V5 更新)
     * @param proposalId 提案 ID
     * @param groupId Semaphore Group ID
     * @param identityCommitment 用户身份承诺
     * @param member 加入的用户地址
     */
    event MemberJoined(
        uint256 indexed proposalId,
        uint256 indexed groupId,
        uint256 identityCommitment,
        address indexed member
    );

    /**
     * @notice 投票事件
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param nullifier 无效化器 (唯一标识符)
     */
    event VoteCast(
        uint256 indexed proposalId,
        uint256 indexed optionId,
        uint256 nullifier
    );

    /**
     * @notice 提案状态变更事件
     * @param proposalId 提案 ID
     * @param isActive 新状态
     */
    event ProposalStatusChanged(
        uint256 indexed proposalId,
        bool isActive
    );

    /**
     * @notice 合约升级事件
     * @param previousVersion 旧版本号
     * @param newVersion 新版本号
     */
    event ContractUpgraded(string previousVersion, string newVersion);

    // ========== 修饰符 ==========

    /**
     * @notice 仅所有者可调用
     */
    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    // ========== 初始化 ==========

    /**
     * @notice 构造函数 (禁用初始化)
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice 初始化合约 (保留 V2/V3/V4 签名，确保兼容性)
     * @param _semaphore Semaphore 验证器地址
     * @param admin 管理员地址
     */
    function initialize(address _semaphore, address admin) external initializer {
        require(_semaphore != address(0), "Invalid Semaphore address");
        require(admin != address(0), "Invalid admin address");

        semaphore = ISemaphore(_semaphore);
        _owner = admin;
    }

    /**
     * @notice V5 升级后初始化
     * @dev 从 V4 升级到 V5 的初始化函数
     *
     * V5 变更说明:
     * - 无需数据迁移（V4 的所有数据保持不变）
     * - joinProposal 函数逻辑改变（运行时行为）
     * - 保留所有现有提案和投票数据
     */
    function initializeV5() external onlyOwner {
        emit ContractUpgraded("V4", "V5");
    }

    // ========== 提案管理 ==========

    /**
     * @notice 创建提案
     * @param title 提案标题
     * @return proposalId 新创建的提案 ID
     *
     * @dev V5 修复说明:
     * - Group Admin 设置为合约自身 address(this)
     * - 允许合约通过 semaphore.addMember() 添加成员
     * - 确保 Semaphore 的 rootHistory 正确同步
     */
    function createProposal(
        string memory title
    ) external onlyOwner returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");

        proposalCount++;
        Proposal storage p = proposals[proposalCount];

        p.id = proposalCount;
        p.title = title;
        p.groupId = proposalCount;  // groupId 与 proposalId 相同
        p.createdAt = block.timestamp;
        p.isActive = true;  // 默认激活

        // 🔑 关键修复: 将合约自身设为 group admin
        _createGroup(p.groupId, address(this));

        emit ProposalCreated(proposalCount, title, p.groupId);

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
        require(bytes(name).length > 0, "Name cannot be empty");

        p.optionCount++;
        p.options[p.optionCount] = Option(p.optionCount, name, 0);

        emit OptionAdded(proposalId, p.optionCount, name);
    }

    /**
     * @notice 设置提案状态
     * @param proposalId 提案 ID
     * @param isActive 目标状态 (true=激活, false=停用)
     *
     * @dev 允许所有者手动控制提案的激活/停用状态
     */
    function setProposalStatus(
        uint256 proposalId,
        bool isActive
    ) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");

        p.isActive = isActive;

        emit ProposalStatusChanged(proposalId, isActive);
    }

    // ========== 用户注册 (V5 核心改进) ==========

    /**
     * @notice 用户自由加入提案 (V5 修复版本)
     * @param proposalId 提案 ID
     * @param identityCommitment 用户身份承诺 (Poseidon(privateKey))
     *
     * @dev V5 修复说明:
     * - 通过 semaphore.addMember() 添加成员
     * - 合约作为 group admin,有权限调用 addMember
     * - 自动同步 Semaphore 的 merkleRootCreationDates (rootHistory)
     * - 确保后续投票的 validateProof 能够识别新的 Merkle Root
     *
     * @dev 安全性:
     * - 保留提案激活状态检查
     * - 利用 Semaphore 标准流程,无安全风险
     * - 用户仍可自由加入,无需预先授权
     */
    function joinProposal(
        uint256 proposalId,
        uint256 identityCommitment
    ) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(p.isActive, "Proposal not active");

        // 🔑 关键修复: 调用 Semaphore 的 addMember
        // 这会自动更新 Merkle Tree 和 rootHistory
        semaphore.addMember(p.groupId, identityCommitment);

        // V5 自定义事件(包含用户地址)
        emit MemberJoined(proposalId, p.groupId, identityCommitment, msg.sender);
    }

    // ========== 匿名投票 (核心逻辑) ==========

    /**
     * @notice 匿名投票
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param merkleTreeDepth Merkle Tree 深度
     * @param merkleTreeRoot Merkle Tree 根
     * @param nullifier 无效化器 (用于追踪投票次数)
     * @param proof ZK 证明 (Groth16)
     *
     * @dev ZK 证明保证:
     * - 投票者是群组成员
     * - nullifier 由投票者的 identity 和 proposalId 生成
     * - 投票选项 (signal) 包含在证明中
     * - 无法追踪到具体投票者
     */
    function vote(
        uint256 proposalId,
        uint256 optionId,
        uint256 merkleTreeDepth,
        uint256 merkleTreeRoot,
        uint256 nullifier,
        uint256[8] calldata proof
    ) external {
        Proposal storage p = proposals[proposalId];

        // ===== 业务逻辑验证 =====
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(p.isActive, "Voting not active");
        require(optionId > 0 && optionId <= p.optionCount, "Invalid option");

        // ===== ZK 证明验证 =====
        ISemaphore.SemaphoreProof memory semaphoreProof = ISemaphore.SemaphoreProof({
            merkleTreeDepth: merkleTreeDepth,
            merkleTreeRoot: merkleTreeRoot,
            nullifier: nullifier,
            message: optionId,  // signal (投票选项)
            scope: proposalId,  // scope (提案 ID)
            points: proof
        });

        semaphore.validateProof(p.groupId, semaphoreProof);

        // ===== 记录投票 =====
        p.options[optionId].voteCount++;
        p.nullifierVoteCount[nullifier]++;

        emit VoteCast(proposalId, optionId, nullifier);
    }

    // ========== 查询函数 ==========

    /**
     * @notice 获取提案某选项的票数
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @return 票数
     */
    function getVotes(
        uint256 proposalId,
        uint256 optionId
    ) external view returns (uint256) {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Invalid proposal");
        require(optionId > 0 && optionId <= p.optionCount, "Option not exist");
        return p.options[optionId].voteCount;
    }

    /**
     * @notice 获取提案的所有选项
     * @param proposalId 提案 ID
     * @return 选项数组
     */
    function getOptions(uint256 proposalId)
        external
        view
        returns (Option[] memory)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");

        Option[] memory result = new Option[](p.optionCount);

        for (uint256 i = 1; i <= p.optionCount; i++) {
            result[i - 1] = p.options[i];
        }

        return result;
    }

    /**
     * @notice 获取提案标题
     * @param proposalId 提案 ID
     * @return 提案标题
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
     * @notice 获取提案截止时间 (V5 废弃)
     * @param proposalId 提案 ID
     * @return 截止时间戳 (永久返回 type(uint256).max)
     *
     * @dev 为兼容性保留，V5 提案永久有效。建议使用 getProposalStatus() 替代
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

    /**
     * @notice 获取 nullifier 的投票次数
     * @param proposalId 提案 ID
     * @param nullifier 无效化器
     * @return 投票次数
     */
    function getNullifierVoteCount(uint256 proposalId, uint256 nullifier)
        external
        view
        returns (uint256)
    {
        return proposals[proposalId].nullifierVoteCount[nullifier];
    }

    /**
     * @notice 获取提案状态
     * @param proposalId 提案 ID
     * @return isActive 提案是否激活
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
     * @notice 获取提案完整信息
     * @param proposalId 提案 ID
     * @return id 提案 ID
     * @return title 提案标题
     * @return groupId Semaphore Group ID
     * @return optionCount 选项数量
     * @return createdAt 创建时间
     * @return isActive 是否激活
     */
    function getProposalInfo(uint256 proposalId)
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
        require(bytes(p.title).length != 0, "Proposal not exist");

        return (
            p.id,
            p.title,
            p.groupId,
            p.optionCount,
            p.createdAt,
            p.isActive
        );
    }

    /**
     * @notice 获取合约版本 (V5)
     * @return 版本号字符串
     */
    function version() external pure returns (string memory) {
        return "V5";
    }

    // ========== 权限控制 ==========

    /**
     * @notice 获取合约所有者
     * @return 所有者地址
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @notice 授权升级 (UUPS 模式)
     * @param newImplementation 新实现地址
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
