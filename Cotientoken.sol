// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";
import "https://github.com/uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract CoTienToken is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant INITIAL_TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1 tỷ COTIEN
    bool public paused;
    address public backupOwner;

    event TokensWithdrawn(address indexed owner, uint256 amount);
    event TokensDeposited(address indexed owner, uint256 amount);
    event Paused(bool paused);
    event EmergencyEthWithdrawn(address indexed owner, uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, address indexed router);
    event BackupOwnerSet(address indexed backupOwner);
    event OwnershipTransferredToBackup(address indexed previousOwner, address indexed newOwner);

    modifier whenNotPaused {
        require(!paused, "Contract is paused");
        _;
    }

    constructor() ERC20("CoTienToken", "COTIEN") {
        _mint(msg.sender, INITIAL_TOTAL_SUPPLY);
    }

    function transfer(address to, uint256 amount) public virtual override whenNotPaused returns (bool) {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Transfer amount must be greater than 0");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount, address router) external onlyOwner nonReentrant {
        require(tokenAmount > 0 && ethAmount > 0, "Invalid liquidity amount");
        require(balanceOf(address(this)) >= tokenAmount, "Insufficient token balance");
        require(address(this).balance >= ethAmount, "Insufficient ETH balance");
        require(router != address(0), "Invalid router address");

        _approve(address(this), router, tokenAmount);
        IUniswapV2Router02(router).addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
        emit LiquidityAdded(tokenAmount, ethAmount, router);
    }

    function withdrawTokens(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        uint256 contractTokenBalance = balanceOf(address(this));
        require(amount <= contractTokenBalance, "Amount exceeds contract balance");
        _transfer(address(this), msg.sender, amount);
        emit TokensWithdrawn(msg.sender, amount);
  
  
  
  
  
  
  
  
  
  
  
  
    }

    function depositTokens(uint256 amount) external onlyOwner whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        _transfer(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    function burn(uint256 amount) external whenNotPaused {
        require(amount > 0, "Amount must be greater than 0");
        _burn(msg.sender, amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function emergencyWithdrawEth(uint256 amount) external onlyOwner nonReentrant {
        uint256 ethBalance = address(this).balance;
        require(amount <= ethBalance, "Insufficient ETH balance");
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Failed to send ETH");
        emit EmergencyEthWithdrawn(msg.sender, amount);
    }

    function setBackupOwner(address _backup) external onlyOwner {
        require(_backup != address(0), "Invalid backup owner address");
        require(_backup != owner(), "Backup cannot be current owner");
        backupOwner = _backup;
        emit BackupOwnerSet(_backup);
    }

    function emergencyTransferOwnership() external {
        require(msg.sender == backupOwner, "Only backup owner can call this");
        require(backupOwner != address(0), "Backup owner not set");
        address previousOwner = owner();
        _transferOwnership(backupOwner);
        emit OwnershipTransferredToBackup(previousOwner, backupOwner);
    }

    receive() external payable {}
}