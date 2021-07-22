// SPDX-License-Identifier: MIT

pragma solidity ^0.6.7;

import "./lib/reentrancy-guard.sol";
import "./lib/owned.sol";
import "./lib/erc20.sol";
import "./lib/safe-math.sol";

contract FeatureStaking is ReentrancyGuard, Owned {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    IERC20 public stakingToken;
    uint256 public unbondingPeriod = 10 minutes;
    
    struct StakingInfo {
        uint256 balance;
        uint256 unlockTime;
        uint256 features;
    }
    mapping(address => StakingInfo) private _stakes;

    uint256 private _totalLocked;
    uint256 private _totalUnbonding;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _owner,
        address _stakingToken
    ) public Owned(_owner) {
        stakingToken = IERC20(_stakingToken);
    }

    /* ========== VIEWS ========== */

    function totalLocked() external view returns (uint256) {
        return _totalLocked;
    }

    function totalUnbonding() external view returns (uint256) {
        return _totalUnbonding;
    }

    function stakedBalanceOf(address account) external view returns (uint256) {
        if (_stakes[account].unlockTime > 0) {
            return 0;
        }
        return _stakes[account].balance;
    }

    function totalBalanceOf(address account) external view returns (uint256) {
        return _stakes[account].balance;
    }

    function unlockTimeOf(address account) external view returns (uint256) {
        return _stakes[account].unlockTime;
    }

    function getStakingInfo(address account) external view returns (uint256, uint256, uint256){
        return (
            _stakes[account].balance,
            _stakes[account].unlockTime,
            _stakes[account].features
        );
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount, uint256 features)
        external
        nonReentrant
    {
        require(amount > 0, "Cannot stake 0");
        _totalLocked = _totalLocked.add(amount);
        if (_stakes[msg.sender].unlockTime > 0 && _stakes[msg.sender].balance > 0){
            _totalUnbonding = _totalUnbonding.sub(_stakes[msg.sender].balance);
        }
        _stakes[msg.sender].unlockTime = 0;
        _stakes[msg.sender].balance = _stakes[msg.sender].balance.add(amount);
        _stakes[msg.sender].features = features;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function unstake()
        external
        nonReentrant    
    {
        require(_stakes[msg.sender].unlockTime == 0, "Already unbonding");
        require(_stakes[msg.sender].balance > 0, "No tokens staked");
        _totalUnbonding = _totalUnbonding.add(_stakes[msg.sender].balance);
        _stakes[msg.sender].unlockTime = block.timestamp + unbondingPeriod;
        emit Unstaked(msg.sender);
    }

    function withdraw()
        external
        nonReentrant
    {
        require(_stakes[msg.sender].balance > 0, "Cannot withdraw 0");
        require(_stakes[msg.sender].unlockTime != 0, "Must unstake before withdraw");
        require(block.timestamp >= _stakes[msg.sender].unlockTime, "Still in unbonding period");
        uint256 senderBalance = _stakes[msg.sender].balance;
        _totalLocked = _totalLocked.sub(senderBalance);
        _totalUnbonding = _totalUnbonding.sub(senderBalance);
        _stakes[msg.sender].balance = 0;
        stakingToken.safeTransfer(msg.sender, senderBalance);
        emit Withdrawn(msg.sender);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Recover non-staking tokens
    function recoverTokens(address tokenAddress, uint256 tokenAmount)
        external
        onlyOwner
    {
        // Cannot recover the staking token
        require(
            tokenAddress != address(stakingToken),
            "Cannot withdraw the staking token"
        );
        IERC20(tokenAddress).safeTransfer(owner, tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }

    // Recover excess staking tokens
    function recoverExcess()
        external
        onlyOwner
    {
        uint256 contractBalance = IERC20(stakingToken).balanceOf(address(this));
        require(
            contractBalance > _totalLocked,
            "There are no excess tokens"
        );
        uint256 excess = contractBalance.sub(_totalLocked);
        IERC20(stakingToken).safeTransfer(owner, excess);
        emit Recovered(address(stakingToken), excess);
    }

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user);
    event Withdrawn(address indexed user);
    event Recovered(address token, uint256 amount);
}
