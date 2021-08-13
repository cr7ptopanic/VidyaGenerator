// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IVault.sol";

/**
 * @title Teller Contract
 */
contract Teller is Ownable, ReentrancyGuard {
    using Address for address;

    /// @notice Event emitted only on construction.
    event TellerDeployed();

    /// @notice Event emitted when teller toggled.
    event TellerToggled(address teller, bool status);

    /// @notice Event emitted when new commitment added.
    event NewCommitmentAdded(
        uint256 bonus,
        uint256 time,
        uint256 penalty,
        uint256 deciAdjustment
    );

    /// @notice Event emitted when commitment toggled.
    event CommitmentToggled(uint256 index, bool status);

    /// @notice Event emitted when owner set the dev address to get the break commitment fees.
    event PurposeSet(address devAddress);

    /// @notice Event emitted when provider deposit the lp tokens.
    event LpDeposited(address provider, uint256 amount);

    /// @notice Event emitted when provider withdrew the lp tokens.
    event Withdrew(address provider, uint256 amount);

    /// @notice Event emitted when provider commit the lp tokens.
    event Commited(address provider, uint256 commitedAmount);

    /// @notice Event emitted when provider break the commitment.
    event CommitmentBroke(address provider, uint256 tokenSentAmount);

    /// @notice Event emitted when provider claimed.
    event Claimed(address provider, bool success);

    IVault Vault;
    IERC20 LpToken;

    struct Provider {
        uint256 LPdeposited;
        uint256 userWeight;
        uint256 committedAmount;
        uint256 lastClaimedTime;
        uint256 commitmentEndTime;
        uint256 commitmentIndex;
    }
    struct Commitment {
        uint256 bonus;
        uint256 duration;
        uint256 penalty;
        uint256 deciAdjustment;
        bool isActive;
    }

    uint256 totalLP;
    uint256 totalWeight;
    uint256 closeTime;

    mapping(address => Provider) providerInfo;
    mapping(address => bool) provider;

    bool open;
    address devAddress;
    bool purpose;

    Commitment[] commitmentInfo;

    modifier isTellerOpen() {
        require(open, "Teller: Teller is not opened.");
        _;
    }

    modifier isProvider() {
        require(provider[msg.sender], "Teller: Caller is not the provider.");
        _;
    }

    /**
     * @dev Constructor function
     * @param _LpToken Interface of LP token
     * @param _Vault Interface of Vault
     */
    constructor(IERC20 _LpToken, IVault _Vault) {
        Vault = _Vault;
        LpToken = _LpToken;
        commitmentInfo.push();

        emit TellerDeployed();
    }

    /**
     * @dev External function to toggle the teller. This function can be called by only owner.
     */
    function toggleTeller() external onlyOwner {
        open = !open;
        closeTime = block.timestamp;

        emit TellerToggled(address(this), open);
    }

    /**
     * @dev External function to add the commitment. This function can be called by only owner.
     * @param _bonus Amount of bonus
     * @param _days Days of duration
     * @param _penalty Number of penalty
     * @param _deciAdjustment Adjustment amount
     */
    function addCommitment(
        uint256 _bonus,
        uint256 _days,
        uint256 _penalty,
        uint256 _deciAdjustment
    ) external onlyOwner {
        Commitment memory holder;

        holder.bonus = _bonus;
        holder.duration = _days * 1 days;
        holder.penalty = _penalty;
        holder.deciAdjustment = _deciAdjustment;
        holder.isActive = true;

        commitmentInfo.push(holder);

        emit NewCommitmentAdded(_bonus, _days, _penalty, _deciAdjustment);
    }

    /**
     * @dev External function to toggle the commitment. This function can be called by only owner.
     * @param _index Commitment index
     */
    function toggleCommitment(uint256 _index) external onlyOwner {
        require(
            0 < _index && _index <= commitmentInfo.length,
            "Teller: Current index is not listed in the commitment array."
        );

        commitmentInfo[_index].isActive = !commitmentInfo[_index].isActive;

        emit CommitmentToggled(_index, commitmentInfo[_index].isActive);
    }

    /**
     * @dev External function to set the dev address to give that address the break commitment fees. This function can be called by only owner.
     * @param _address Dev address
     */
    function setPurpose(address _address) external onlyOwner {
        purpose = true;
        devAddress = _address;

        emit PurposeSet(devAddress);
    }

    /**
     * @dev External function to deposit lp token from providers. Teller must be open.
     * @param _amount LP token amount
     */
    function depositLP(uint256 _amount) external isTellerOpen {
        LpToken.transferFrom(msg.sender, address(this), _amount);

        Provider storage user = providerInfo[msg.sender];
        if (provider[msg.sender]) {
            claim();
        } else {
            user.lastClaimedTime = block.timestamp;
        }
        user.LPdeposited += _amount;
        user.userWeight += _amount;
        totalLP += _amount;
        provider[msg.sender] = true;

        emit LpDeposited(msg.sender, _amount);
    }

    /**
     * @dev External function to withdraw lp token from providers. This function can be called by only provider.
     * @param _amount LP token amount
     */
    function withdraw(uint256 _amount) external isProvider nonReentrant {
        Provider storage user = providerInfo[msg.sender];
        require(
            user.LPdeposited - user.committedAmount >= _amount,
            "Teller: Provider hasn't got enough deposited LP tokens to withdraw."
        );
        claim();

        user.userWeight -= ((_amount * user.userWeight) / user.LPdeposited);

        user.LPdeposited -= _amount;

        if (user.LPdeposited == 0) {
            provider[msg.sender] = false;
        }

        uint256 balance = LpToken.balanceOf(address(this));
        uint256 send = _amount;

        if (totalLP < balance) {
            send = (_amount * balance) / totalLP;
        }

        totalLP -= send;
        LpToken.transfer(msg.sender, send);

        emit Withdrew(msg.sender, send);
    }

    /**
     * @dev External function to commit lp token to gain a minor advantise for a selected amount of time. This function can be called by only provider.
     * @param _amount LP token amount
     * @param _commitmentIndex Index of commitment array
     */
    function commit(uint256 _amount, uint256 _commitmentIndex)
        external
        nonReentrant
        isProvider
    {
        require(
            commitmentInfo[_commitmentIndex].isActive,
            "Teller: Current commitment is not active."
        );

        Provider storage user = providerInfo[msg.sender];

        require(
            user.LPdeposited - user.committedAmount >= _amount,
            "Teller: Provider hasn't got enough deposited LP tokens to commit."
        );

        uint256 bonusCredit = commitBonus(_commitmentIndex, _amount);
        uint256 newEndTime;

        if (user.commitmentEndTime > block.timestamp) {
            require(
                _commitmentIndex == user.commitmentIndex,
                "Teller: Current commitment is not same as provider's."
            );
            newEndTime = calculateNewEndTime(
                user.committedAmount,
                _amount,
                user.commitmentEndTime,
                _commitmentIndex
            );
        } else {
            newEndTime =
                block.timestamp +
                commitmentInfo[_commitmentIndex].duration;
        }

        user.committedAmount += _amount;
        user.commitmentEndTime = newEndTime;
        user.userWeight += bonusCredit;
        totalWeight += bonusCredit;

        emit Commited(msg.sender, _amount);
    }

    /**
     * @dev External function to break the commitment. This function can be called by only provider.
     */
    function breakCommitment() external nonReentrant isProvider {
        Provider storage user = providerInfo[msg.sender];
        Provider storage blank;

        require(
            user.commitmentEndTime > block.timestamp,
            "Teller: No commitment to break."
        );

        uint256 tokenToReceive = user.LPdeposited;

        Commitment memory currentCommit = commitmentInfo[user.commitmentIndex];

        uint256 fee = (tokenToReceive * currentCommit.penalty) /
            currentCommit.deciAdjustment;

        tokenToReceive -= fee;

        totalLP -= user.LPdeposited;

        totalWeight -= user.userWeight;

        user = blank;

        if (purpose) {
            LpToken.transfer(devAddress, fee / 10);
        }

        LpToken.transfer(msg.sender, tokenToReceive);

        emit CommitmentBroke(msg.sender, tokenToReceive);
    }

    /**
     * @dev External function to claim the vidya token. This function can be called by only provider and teller must be opened.
     */
    function claim() private {
        Provider memory user = providerInfo[msg.sender];
        uint256 timeGap = block.timestamp - user.lastClaimedTime;

        if (!open) {
            timeGap = closeTime - user.lastClaimedTime;
        }

        if (timeGap > 365 * 1 days) {
            timeGap = 365 * 1 days;
        }

        uint256 timeWeight = timeGap * user.userWeight;

        providerInfo[msg.sender].lastClaimedTime = block.timestamp;

        Vault.payProvider(msg.sender, timeWeight, totalWeight);

        emit Claimed(msg.sender, true);
    }

    /**
     * @dev Private function to return commit bonus.
     * @param _commitmentIndex Index of commitment array
     * @param _amount Commitment token amount
     */
    function commitBonus(uint256 _commitmentIndex, uint256 _amount)
        private
        view
        returns (uint256)
    {
        if (commitmentInfo[_commitmentIndex].isActive) {
            return
                (commitmentInfo[_commitmentIndex].bonus * _amount) /
                commitmentInfo[_commitmentIndex].deciAdjustment;
        }
        return 0;
    }

    /**
     * @dev Private function to calculate the new ending time when the current end time is overflown.
     * @param _oldAmount Commitment lp token amount which provider has
     * @param _extraAmount Lp token amount which user wants to commit
     * @param _oldEndTime Previous commitment ending time
     * @param _commitmentIndex Index of commitment array
     */
    function calculateNewEndTime(
        uint256 _oldAmount,
        uint256 _extraAmount,
        uint256 _oldEndTime,
        uint256 _commitmentIndex
    ) private view returns (uint256) {
        uint256 extraEndTIme = commitmentInfo[_commitmentIndex].duration +
            block.timestamp;
        uint256 newEndTime = ((_oldAmount * _oldEndTime) +
            (_extraAmount * extraEndTIme)) / (_oldAmount + _extraAmount);

        return newEndTime;
    }

    /**
     * @dev External function to claim the vidya token. This function can be called by only provider and teller must be opened.
     */
    function claimExternal() external isTellerOpen isProvider {
        claim();

        emit Claimed(msg.sender, true);
    }
}
