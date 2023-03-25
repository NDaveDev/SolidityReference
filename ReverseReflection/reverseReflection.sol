// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is IERC20, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Constants
    uint256 public constant REFLECTION_RATE_DECIMALS = 10000; // 4 decimals
    uint256 public constant MIN_HOLDING_TIME = 7 days;
    uint256 public constant MAX_PENALTY_RATE = 1000; // 10%
    uint256 public constant REBASE_INTERVAL = 1 days;

    // Variables
    uint256 public reflectionRate;
    uint256 public penaltyRate;
    uint256 public lastRebase;
    uint256 public totalFees;
    uint256 public reserveBalance;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => bool) public isExcludedFromFees;

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 totalSupply_,
        address initialHolder_,
        uint256 reflectionRate_,
        uint256 penaltyRate_
    ) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = totalSupply_ * (10 ** decimals_);
        _balances[initialHolder_] = _totalSupply;
        reflectionRate = reflectionRate_;
        penaltyRate = penaltyRate_;
        emit Transfer(address(0), initialHolder_, _totalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            msg.sender,
            _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance")
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
    _approve(
        msg.sender,
        spender,
        _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero")
    );
    return true;
    }

    function isExcludedFromFee(address account) external view returns (bool) {
        return isExcludedFromFees[account];
    }

    function excludeFromFee(address account) external onlyOwner {
        isExcludedFromFees[account] = true;
    }

    function includeInFee(address account) external onlyOwner {
        isExcludedFromFees[account] = false;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        uint256 fee = calculateFee(amount);
        if (!isExcludedFromFees[sender]) {
            reserveBalance += fee;
            totalFees += fee;
            _balances[address(this)] += fee;
            emit Transfer(sender, address(this), fee);
        }

        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount - fee;
        lastUpdateTime[sender] = block.timestamp;
        lastUpdateTime[recipient] = block.timestamp;

        emit Transfer(sender, recipient, amount - fee);
    }

    function calculateFee(uint256 _amount) public view returns (uint256) {
        uint256 fee = (_amount * reflectionRate) / REFLECTION_RATE_DECIMALS;
        if (fee > reserveBalance) {
            fee = reserveBalance;
        }
        return fee;
    }

    function calculatePenalty(address _holder) public view returns (uint256) {
        uint256 holdingTime = block.timestamp - lastUpdateTime[_holder];
        if (holdingTime >= MIN_HOLDING_TIME) {
            return (balances[_holder] * holdingTime * penaltyRate) / (365 days * REFLECTION_RATE_DECIMALS);
        } else {
            return 0;
        }
    }

    function calculateAverageHoldingTime() public view returns (uint256) {
        uint256 totalBalance;
        uint256 totalHoldingTime;
        uint256 totalHolders;
        for (uint256 i = 0; i < _totalSupply; i++) {
            address holder = holderAt(i);
            uint256 balance = balances[holder];
            if (balance > 0) {
                uint256 holdingTime = block.timestamp - lastUpdateTime[holder];
                if (holdingTime >= MIN_HOLDING_TIME) {
                    totalBalance += balance;
                    totalHoldingTime += holdingTime * balance;
                    totalHolders++;
                }
            }
        }
        if (totalHolders > 0) {
            return totalHoldingTime / totalBalance;
        } else {
            return 0;
        }
    }

    function rebase() external {
        require(block.timestamp - lastRebase >= REBASE_INTERVAL, "Rebase not yet available");
        uint256 averageHoldingTime = calculateAverageHoldingTime();
        penaltyRate = (averageHoldingTime * MAX_PENALTY_RATE) / MIN_HOLDING_TIME;
        lastRebase = block.timestamp;
    }

    function withdrawReserve() external onlyOwner {
        uint256 amount = reserveBalance;
        reserveBalance = 0;
        _balances[address(this)] -= amount;
        _balances[owner()] += amount;
        emit Transfer(address(this), owner(), amount);
    }

    function holderAt(uint256 index) public view returns (address) {
        bytes20 holderBytes = bytes20(address(this));
        holderBytes &= bytes20(bytes32(index + 1) << 96);
        return address(holderBytes);
    }

}
