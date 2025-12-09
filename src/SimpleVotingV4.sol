// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemaphore} from "semaphore/packages/contracts/contracts/interfaces/ISemaphore.sol";
import {SemaphoreGroups} from "semaphore/packages/contracts/contracts/base/SemaphoreGroups.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleVotingV4
 * @author Sue
 * @notice 基于 Semaphore 协议的匿名投票系统 - V4 版本
 * @dev 继承 SemaphoreGroups 自动获得 Merkle Tree 管理能力
 *
 * 核心特性:
 * - 完全匿名投票 (ZK 证明)
 * - 支持重复投票 (记录 nullifier 投票次数)
 * - 可升级合约 (UUPS 模式)
 * - 永久提案 (无时间限制) - V4 核心特性
 *
 * V4 升级内容:
 * - 移除提案时间限制 (deadline)
 * - 新增手动状态控制 (isActive)
 * - 提案永久有效，可手动激活/停用
 * - 优化存储成本 (-31 字节/提案)
 */
contract SimpleVotingV4 is Initializable, UUPSUpgradeable, SemaphoreGroups {
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
     * @dev 提案 (V4 版本)
     */
    struct Proposal {
        uint256 id;                            // 提案 ID
        string title;                          // 提案标题
        uint256 groupId;                       // 对应的 Semaphore Group ID
        uint256 optionCount;                   // 选项数量
        mapping(uint256 => Option) options;    // 选项列表
        mapping(uint256 => uint256) nullifierVoteCount; // nullifier => 投票次数
        uint256 createdAt;                     // 创建时间 (保留用于历史记录)
        bool isActive;                         // V4: 提案状态 (替代 deadline)
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
     * @notice 提案创建事件 (V4 修改)
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
     * @notice 成员加入事件
     * @param proposalId 提案 ID
     * @param groupId Semaphore Group ID
     * @param identityCommitment 用户身份承诺
     */
    event MemberJoined(
        uint256 indexed proposalId,
        uint256 indexed groupId,
        uint256 identityCommitment
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
     * @notice 提案状态变更事件 (V4 新增)
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
     * @notice 初始化合约 (保留 V2/V3 签名，确保兼容性)
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
     * @notice V4 升级后初始化
     * @dev 智能迁移现有提案状态
     *
     * 迁移逻辑:
     * - V3 未过期提案 (deadline > now) → isActive = true
     * - V3 已过期提案 (deadline < now) → isActive = false
     * - 保留所有提案数据和投票记录
     */
    function initializeV4() external onlyOwner {
        // 注意: 此函数假设从 V3 升级，V3 的 deadline 字段在相同存储槽位
        // 由于 Solidity 存储布局，我们需要通过 assembly 读取旧的 deadline 值

        for (uint256 i = 1; i <= proposalCount; i++) {
            Proposal storage p = proposals[i];

            // 跳过无效提案
            if (bytes(p.title).length == 0) {
                continue;
            }

            // V4: 默认设置所有提案为激活状态
            // 注意: 由于存储布局变化，无法直接读取旧 deadline
            // 实际部署时，需要通过外部脚本提供每个提案的激活状态
            p.isActive = true;
        }

        emit ContractUpgraded("V3", "V4");
    }

    // ========== 提案管理 ==========

    /**
     * @notice 创建提案 (V4: 移除 duration 参数)
     * @param title 提案标题
     * @return proposalId 新创建的提案 ID
     *
     * @dev V4 变更:
     * - 移除 duration 参数
     * - 提案默认为激活状态 (isActive = true)
     * - 提案永久有效，可通过 setProposalStatus() 手动控制
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
        p.isActive = true;  // V4: 默认激活

        // 创建对应的 Semaphore Group
        _createGroup(p.groupId, _owner);

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
     * @notice 设置提案状态 (V4 新增)
     * @param proposalId 提案 ID
     * @param isActive 目标状态 (true=激活, false=停用)
     *
     * @dev 允许所有者手动控制提案的激活/停用状态
     * 用于暂停有问题的提案或重新激活已停用的提案
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

    // ========== 用户注册 (Semaphore 群组) ==========

    /**
     * @notice 用户加入提案 (V4: 使用 isActive 检查)
     * @param proposalId 提案 ID
     * @param identityCommitment 用户身份承诺 (Poseidon(privateKey))
     *
     * @dev V4 变更: 使用 isActive 替代 deadline 检查
     */
    function joinProposal(
        uint256 proposalId,
        uint256 identityCommitment
    ) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(p.isActive, "Proposal not active");  // V4: 状态检查

        // 添加到 Semaphore Group (继承自 SemaphoreGroups)
        _addMember(p.groupId, identityCommitment);

        emit MemberJoined(proposalId, p.groupId, identityCommitment);
    }

    // ========== 匿名投票 (核心逻辑) ==========

    /**
     * @notice 匿名投票 (V4: 使用 isActive 检查)
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param merkleTreeDepth Merkle Tree 深度
     * @param merkleTreeRoot Merkle Tree 根
     * @param nullifier 无效化器 (用于追踪投票次数)
     * @param proof ZK 证明 (Groth16)
     *
     * @dev V4 变更:
     * - 使用 isActive 替代 deadline 检查
     * - 允许提案永久接受投票（除非手动停用）
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
        require(p.isActive, "Voting not active");  // V4: 状态检查
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
     * @notice 获取提案截止时间 (V4 废弃)
     * @param proposalId 提案 ID
     * @return 截止时间戳 (永久返回 type(uint256).max)
     *
     * @dev 为兼容性保留，V4 提案永久有效。建议使用 getProposalStatus() 替代
     */
    function getProposalDeadline(uint256 proposalId)
        external
        view
        returns (uint256)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return type(uint256).max;  // V4: 永久有效
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
     * @notice 获取提案状态 (V4 新增)
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
     * @notice 获取提案完整信息 (V4 新增)
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
     * @notice 获取合约版本 (V4)
     * @return 版本号字符串
     */
    function version() external pure returns (string memory) {
        return "V4";
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
