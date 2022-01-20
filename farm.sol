// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./@openzeppelin/contracts/access/Ownable.sol";
import "./@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./@openzeppelin/contracts/utils/math/Math.sol";
import "./@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract XFT_FARM is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeMath for int;
    IBEP20 xft;
    IBEP20 LP;
    uint256 public xftPerShare;
    uint256 public xftPerBlock;
    uint256 public lastBlock;
    bool pause;
    struct UserInfo {
        uint256 amount;
        uint prevBlock;
    }

    mapping (address => UserInfo) public Stakers;

    constructor(address _xft, address _LP, uint256 _perBlock) {
        xft = IBEP20(_xft);
        LP = IBEP20(_LP);
        xftPerBlock = _perBlock;
        lastBlock = block.number;
        pause = false;
    }

    modifier paused() {
        require(!pause, "farm is paused");
        _;
    }
    
    modifier deposited() {
        require(Stakers[msg.sender].amount > 0, "You have 0 deposits");
        _;
    }

    function getPending(address caller) public view returns(uint256){
        uint256 shareOfStake = Stakers[caller].amount.div(LP.balanceOf(address(this)));
        uint256 blocksPassed = uint256(block.number).sub(uint256(Stakers[caller].prevBlock));
        uint256 xftBlocks = xftPerBlock.mul(blocksPassed);
        return xftBlocks.mul(shareOfStake);

    }

    function deposit(uint256 amount) public paused nonReentrant{
        require(LP.allowance(msg.sender, address(this)) >= amount, "You must approve the amount of tokens you wish to stake");
        uint256 pending = getPending(msg.sender);
        if (pending > 0) {
            xft.transferFrom(address(this), msg.sender, pending);
            
        }
        LP.transferFrom(msg.sender, address(this), amount);
        Stakers[msg.sender].amount += amount;
        lastBlock = block.number;
        Stakers[msg.sender].prevBlock = block.number;

    }

    function withdraw(uint256 amount) public paused deposited nonReentrant{
        require(amount <= Stakers[msg.sender].amount, "You cannot withdraw more than your current deposit");
        uint256 pending = getPending(msg.sender);
        if (pending > 0) {
            xft.transferFrom(address(this), msg.sender, pending);
        }
        LP.transferFrom(address(this), msg.sender, amount);
        Stakers[msg.sender].amount -= amount;
        lastBlock = block.number;
        Stakers[msg.sender].prevBlock = block.number;


    }

    function emergencyWithdraw() public deposited nonReentrant{
        UserInfo storage user = Stakers[msg.sender];

        LP.transfer(msg.sender, user.amount);

        user.amount = 0;
    }

    function harvest() public paused deposited nonReentrant{
        uint256 pending = getPending(msg.sender);
        require(xft.balanceOf(address(this)) > pending, "Not enough XFT in the Farm");
        if (pending > 0) {
            xft.transferFrom(address(this), msg.sender, pending);
        }
        lastBlock = block.number;
        Stakers[msg.sender].prevBlock = block.number;

    }

    function stop() public onlyOwner{
        pause = !pause;
    }

    function adjustPerBlock(uint256 perBlock) public onlyOwner{
        xftPerBlock = perBlock;
    }
}
