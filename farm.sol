// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./@openzeppelin/contracts/access/Ownable.sol";
import "./@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./@openzeppelin/contracts/utils/math/Math.sol";
import "./@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./@openzeppelin/contracts/utils/math/SignedSafeMath.sol";

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
    using SignedSafeMath for int256;
    IBEP20 xft;
    IBEP20 LP;
    uint256 public xftPerShare;
    uint256 public xftPerBlock;
    uint256 public lastBlock;
    bool pause;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
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
        require(Stakers[msg.sender].amount > 0, "0 deposits");
        _;
    }

    function update_farm() internal {
        if(block.number > lastBlock ){
            uint256 lp_supply = LP.balanceOf(address(this));
            if(lp_supply != 0){
                uint256 blocks = block.number.sub(lastBlock);
                uint256 reward = blocks.mul(xftPerBlock);
                xftPerShare = xftPerShare.add((reward.mul(1e18) / lp_supply));
            }
            lastBlock = block.number;
        }
    }

    function getPending() public view returns(uint256){
        UserInfo storage user = Stakers[msg.sender];
        uint256 lp_supply = LP.balanceOf(address(this));
        uint256 perShare = xftPerShare;
        if (block.number > lastBlock && lp_supply > 0){
            uint256 blocks = block.number.sub(lastBlock);
            uint256 xftReward = blocks.mul(xftPerBlock);
            perShare = xftPerShare.add(xftReward.mul(1e18) / lp_supply);
        }
        return uint256(int256(user.amount.mul(perShare) / 1e18) - user.rewardDebt);
    }

    function deposit(uint256 amount) public paused nonReentrant{
        require(LP.allowance(msg.sender, address(this)) >= amount, "approve");
        
        update_farm();
        UserInfo storage user = Stakers[msg.sender];

        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(int256(user.amount.mul(xftPerShare).div(1e18)));

        LP.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public paused deposited nonReentrant{
        update_farm();
        UserInfo storage user = Stakers[msg.sender];
        uint256 pending = getPending();

        require(pending <= xft.balanceOf(address(this)), "farm is drained");

        user.rewardDebt = user.rewardDebt.sub(int256(user.amount.mul(xftPerShare).div(1e18)));
        user.amount = user.amount.sub(amount);

        xft.transfer(msg.sender, pending);
        LP.transfer(msg.sender, amount);
    }

    function emergencyWithdraw() public deposited nonReentrant{
        UserInfo storage user = Stakers[msg.sender];

        LP.transfer(msg.sender, user.amount);

        user.amount = 0;
        user.rewardDebt = 0;
    }

    function harvest() public paused deposited nonReentrant{
        update_farm();
        UserInfo storage user = Stakers[msg.sender];
        
        uint256 pending = getPending();
        require(pending <= xft.balanceOf(address(this)), "farm is drained");
        
        user.rewardDebt = int256(user.amount.mul(xftPerShare).div(1e18));

        if (pending != 0) {
            xft.transfer(msg.sender, pending);
        }
    }

    function stop() public onlyOwner{
        pause = !pause;
    }

    function adjustPerBlock(uint256 perBlock) public onlyOwner{
        xftPerBlock = perBlock;
    }
}
