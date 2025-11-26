// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Initializable} from "openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts/contracts/proxy/utils/UUPSUpgradeable.sol";

contract SimpleVoting is Initializable, UUPSUpgradeable{
    struct Option {
        uint256 id;
        string name;
        uint256 voteCount;
    }

    struct Proposal {
        uint256 id;
        string title;//提案标题
        uint256 optionCount;
        mapping(uint256 => Option) options;//选项列表
        mapping(address => bool) hasVoted;//记录每一个地址对该提案是否投票
    }

    address private _owner;
    uint256 public proposalCount;
    uint256 public num;
    //ProposalId => Proposal
    mapping(uint256 => Proposal) public proposals;

    event ProposalCreated(uint256 proposalId,string title);
    event OptionAdded(uint256 proposalId,uint256 optionId,string name);
    event Voted(address indexed voter,uint256 proposalId,uint256 optionId);

    constructor() {
        _disableInitializers();
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Not owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function initialize(address admin) external initializer {
        _owner = admin;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner{}
    /**
     * 创造提案
     * @param title 提案名称
     */
    function createProposal(string memory title) external onlyOwner{
        proposalCount += 1;
        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.title = title;
    }
    /**
     * 未提案增加一个选项
     * @param proposalId 提案ID
     * @param optionName 提案内容
     */
    function addOption(uint256 proposalId,string calldata optionName) external onlyOwner {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length !=0 ,"Proposal not exist");

        p.optionCount += 1;
        p.options[p.optionCount] = Option(p.optionCount,optionName,0);
        emit OptionAdded(proposalId, p.optionCount, optionName);
    }

    /**
     * 投票 对提案一个选项
     * @param proposalId 提案ID
     */
     function vote(uint256 proposalId,uint256 optionId) external {
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length !=0 ,"proposals not exist");
        require(optionId > 0 && optionId <= p.optionCount,"Option not exist");
        require(!p.hasVoted[msg.sender],"Alreadly Voted");
        p.options[optionId].voteCount += 1;
        p.hasVoted[msg.sender] = true;

        emit Voted(msg.sender,proposalId,optionId);
     }

    /**
     * 拿到投票票数
     * @param proposalId 提案ID
     */
    function getVotes(uint256 proposalId,uint256 optionId) external view returns (uint256){
        Proposal storage p = proposals[proposalId];
        require(bytes(p.title).length != 0,"Invalid proposal");
        require(optionId > 0 && optionId <= p.optionCount,"Option not exist");
        return p.options[optionId].voteCount;
    }

    function getOptions(uint256 proposalId) external view returns (Option[] memory){
        Proposal storage p = proposals[proposalId];
        Option[] memory result = new Option[](p.optionCount);
        for(uint64 i = 1;i<= p.optionCount;i++){
            Option storage o = p.options[i];
            result[i-1] = o;
        }
        return result;
    }
 }