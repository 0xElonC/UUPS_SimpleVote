// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISemaphore} from "semaphore/packages/contracts/contracts/interfaces/ISemaphore.sol";
import {SemaphoreGroups} from "semaphore/packages/contracts/contracts/base/SemaphoreGroups.sol";
import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title SimpleVotingV3
 * @author Sue
 * @notice 基于 Semaphore 协议的匿名投票系统 - V3 版本
 * @dev 继承 SemaphoreGroups 自动获得 Merkle Tree 管理能力
 *
 * 核心特性:
 * - 完全匿名投票 (ZK 证明)
 * - 支持重复投票 (记录 nullifier 投票次数) - V3 新增
 * - 可升级合约 (UUPS 模式)
 * - 保留原有业务逻辑
 * 
 * V3 升级内容:
 * - 允许用户对同一提案无限次投票
 * - 记录每个 nullifier 的投票次数
 * - 移除重复投票限制
 * - 新增投票次数查询函数
 */
contract SimpleVotingV3 is Initializable, UUPSUpgradeable, SemaphoreGroups {
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
     * @dev 提案
     */
    struct Proposal {
        uint256 id;                            // 提案 ID
        string title;                          // 提案标题
        uint256 groupId;                       // 对应的 Semaphore Group ID
        uint256 optionCount;                   // 选项数量
        mapping(uint256 => Option) options;    // 选项列表
        mapping(uint256 => uint256) nullifierVoteCount; // nullifier => 投票次数 (V3: 从 bool 改为 uint256)
        uint256 createdAt;                     // 创建时间
        uint256 deadline;                      // 投票截止时间
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
     * @param deadline 投票截止时间
     */
    event ProposalCreated(
        uint256 indexed proposalId,
        string title,
        uint256 groupId,
        uint256 deadline
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
     * @notice 合约升级事件 (V3 新增)
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
     * @notice 初始化合约 (保留V2签名，确保兼容性)
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
     * @notice V3 升级后初始化 (可选)
     * @dev 如果需要在升级后执行额外逻辑，可以调用此函数
     */
    function initializeV3() external onlyOwner {
        emit ContractUpgraded("V2", "V3");
    }

    // ========== 提案管理 (保留原有逻辑) ==========

    /**
     * @notice 创建提案
     * @param title 提案标题
     * @param duration 投票持续时间 (秒)
     * @return proposalId 新创建的提案 ID
     *
     * @dev 自动创建对应的 Semaphore Group
     */
    function createProposal(
        string memory title,
        uint256 duration
    ) external onlyOwner returns (uint256) {
        require(bytes(title).length > 0, "Title cannot be empty");
        require(duration > 0, "Duration must be positive");

        proposalCount++;
        Proposal storage p = proposals[proposalCount];

        p.id = proposalCount;
        p.title = title;
        p.groupId = proposalCount;  // groupId 与 proposalId 相同
        p.createdAt = block.timestamp;
        p.deadline = block.timestamp + duration;

        // 创建对应的 Semaphore Group
        _createGroup(p.groupId, _owner);

        emit ProposalCreated(proposalCount, title, p.groupId, p.deadline);

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

    // ========== 用户注册 (Semaphore 群组) ==========

    /**
     * @notice 用户加入提案
     * @param proposalId 提案 ID
     * @param identityCommitment 用户身份承诺 (Poseidon(privateKey))
     *
     * @dev identityCommitment 无法反推 privateKey, 保证隐私
     */
    function joinProposal(
        uint256 proposalId,
        uint256 identityCommitment
    ) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        require(block.timestamp < p.deadline, "Proposal expired");

        // 添加到 Semaphore Group (继承自 SemaphoreGroups)
        _addMember(p.groupId, identityCommitment);

        emit MemberJoined(proposalId, p.groupId, identityCommitment);
    }

    // ========== 匿名投票 (核心逻辑 - V3 修改) ==========

    /**
     * @notice 匿名投票
     * @param proposalId 提案 ID
     * @param optionId 选项 ID
     * @param merkleTreeDepth Merkle Tree 深度
     * @param merkleTreeRoot Merkle Tree 根
     * @param nullifier 无效化器 (用于追踪投票次数)
     * @param proof ZK 证明 (Groth16)
     *
     * @dev 工作流程:
     * 1. 验证业务逻辑 (提案存在、未过期、选项合法) - V3: 移除 nullifier 重复检查
     * 2. 验证 ZK 证明 (调用 Semaphore 验证器)
     * 3. 记录投票 (增加票数、递增 nullifier 计数) - V3: 改为计数而非标记
     *
     * @dev ZK 证明保证:
     * - 投票者是群组成员
     * - nullifier 由投票者的 identity 和 proposalId 生成
     * - 投票选项 (signal) 包含在证明中
     * - 无法追踪到具体投票者
     * 
     * @dev V3 变更:
     * - 允许同一 nullifier 多次投票
     * - 记录每次投票，累加 nullifierVoteCount
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
        require(block.timestamp < p.deadline, "Voting ended");
        require(optionId > 0 && optionId <= p.optionCount, "Invalid option");
        // V3: 移除了 require(!p.usedNullifiers[nullifier], "Already voted")

        // ===== ZK 证明验证 =====
        // 验证:
        // 1. 证明有效性
        // 2. nullifier 由群组成员的 identity 生成
        // 3. signal (optionId) 包含在证明中
        // 4. Merkle Tree Root 匹配

        // 构建 SemaphoreProof 结构体
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
        p.nullifierVoteCount[nullifier]++; // V3: 递增计数 (而非设为 true)

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
     * @notice 获取提案截止时间
     * @param proposalId 提案 ID
     * @return 截止时间戳
     */
    function getProposalDeadline(uint256 proposalId)
        external
        view
        returns (uint256)
    {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0, "Proposal not exist");
        return p.deadline;
    }

    /**
     * @notice 获取 nullifier 的投票次数 (V3 新增)
     * @param proposalId 提案 ID
     * @param nullifier 无效化器
     * @return 投票次数
     * 
     * @dev V3: 替代 V2 的 isNullifierUsed，返回投票次数而非布尔值
     */
    function getNullifierVoteCount(uint256 proposalId, uint256 nullifier)
        external
        view
        returns (uint256)
    {
        return proposals[proposalId].nullifierVoteCount[nullifier];
    }

    /**
     * @notice 获取合约版本 (V3 新增)
     * @return 版本号字符串
     */
    function version() external pure returns (string memory) {
        return "V3";
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
