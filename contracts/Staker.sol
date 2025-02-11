// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RewardToken.sol";
// https://docs.openzeppelin.com/contracts/4.x/api/token/erc20#SafeERC20
// Security: wrapper that throw and revert on failure, allows safe calls operations 
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// https://docs.openzeppelin.com/contracts/4.x/api/security#ReentrancyGuard
// Security: prevent reentrant call in a specific function 
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@openzeppelin/contracts/access/Ownable.sol";

contract Staker is ReentrancyGuard, Ownable {
  using SafeERC20 for RewardToken;

  event InitStake(uint256 _internalSupply, address by, uint256 _lockSeconds, uint256 timestamp);
  event Deposit(uint256 ammount, address by, uint256 timestamp);
  event Withdraw(uint256 ammount, address by, uint256 timestamp);
  event ClaimReward(uint256 ammount, address by, uint256 timestamp);

  RewardToken public immutable rewardToken;

  struct StakerInfo {
    uint256 balance;
    uint256 stakingEndTimestamp;
  }

  mapping (address => StakerInfo) public stakers;

  uint256 public lockSeconds;
  uint256 public lastBlockNumber;
  uint256 public totalSupply;
  uint256 public internalSupply;
  uint256 public totalStakers;

  constructor(address _rewardToken) {
    rewardToken = RewardToken(_rewardToken);
  }

  function initStake(uint256 _internalSupply, uint256 _lockSeconds) external onlyOwner {
    require(lastBlockNumber == 0, "stake already inited");
    require(_lockSeconds > 0, "invalid _lockSeconds");

    lockSeconds = _lockSeconds;
    lastBlockNumber = block.number;
    internalSupply = _internalSupply;

    rewardToken.mint(address(this), _internalSupply);

    emit InitStake(_internalSupply, msg.sender, _lockSeconds, block.timestamp);
  }

  /**
    For each block mined, 100 tokens should be minted
    and added to the internalSupply for later distribution
   */
  function updateInternalSupply() public {
    if (block.number <= lastBlockNumber) {
      return;
    }

    uint256 blocks = block.number - lastBlockNumber;
    internalSupply += 100 * (10 ** rewardToken.decimals()) * blocks;
    lastBlockNumber = block.number;

    rewardToken.mint(address(this), 100 * (10 ** rewardToken.decimals()) * blocks);
  }

  function deposit(uint256 ammount) external nonReentrant {
    require(lastBlockNumber != 0, "deposit unavailable, stake not inited yet");
    require(ammount > 0, "ammount must be greater than 0");

    if (stakers[msg.sender].balance == 0) {
      totalStakers += 1;
    }

    totalSupply += ammount;
    stakers[msg.sender].balance += ammount;
    stakers[msg.sender].stakingEndTimestamp = block.timestamp + lockSeconds;

    updateInternalSupply();

    rewardToken.safeTransferFrom(msg.sender, address(this), ammount);

    emit Deposit(ammount, msg.sender, block.timestamp);
  }

  /**
    Returns the staked 
    balance plus the internalSupply reward 
    without the stakeReward as this one must be minted
   */
  function getInternalSupplyReward(address from) internal view returns (uint256) {
    uint256 stakeRate = totalSupply / stakers[from].balance;
    return internalSupply / stakeRate;
  }

  /**
    Withdraw the staked balance 
    plus the internalSupply reward 
    plus the stakeReward, this one must be minted
   */
  function withdraw() external nonReentrant {
    require(lastBlockNumber != 0, "withdraw unavailable, stake not inited yet");
    require(stakers[msg.sender].stakingEndTimestamp < block.timestamp, "withdraw unavailable by timestamp");
    require(stakers[msg.sender].balance > 0, "no balance staked");

    updateInternalSupply();
    
    uint256 internalSupplyReward = getInternalSupplyReward(msg.sender);
    uint256 totalWithdraw = internalSupplyReward + stakers[msg.sender].balance;
    uint256 stakeRewards = (stakers[msg.sender].balance * rewardToken.rewardRate()) / 1000;

    if (rewardToken.withdrawFeeEnable()) {
      totalWithdraw -= totalWithdraw * rewardToken.withdrawFee() / 1000;
      stakeRewards -= stakeRewards * rewardToken.withdrawFee() / 1000;
    }

    internalSupply -= internalSupplyReward;
    totalSupply -= stakers[msg.sender].balance;
    stakers[msg.sender].balance = 0;
    totalStakers -= 1;

    rewardToken.mint(address(this), stakeRewards);
    rewardToken.safeTransfer(msg.sender, totalWithdraw + stakeRewards);

    emit Withdraw(totalWithdraw + stakeRewards, msg.sender, block.timestamp);
  }
}
