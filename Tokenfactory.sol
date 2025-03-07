// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

// Định nghĩa interface IUniswapV2Router02 trong cùng file
interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

// Định nghĩa hợp đồng chính TokenFactory
contract TokenFactory is ERC20, Ownable, ReentrancyGuard, EIP712 {
    uint256 public constant INITIAL_TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MAX_MINT_AMOUNT = 1_000_000_000 * 10**18;
    uint256 public constant TOTAL_SUPPLY_CAP = INITIAL_TOTAL_SUPPLY * 2;
    uint256 public constant MINT_COOLDOWN = 1 days;
    uint256 public constant BATCH_COOLDOWN = 1 hours;

    bool public paused;
    address public backupOwner;
    string public compilerVersion;
    address public currentRouter;
    uint256 public deploymentTimestamp;
    uint256 public lastMintTimestamp;
    uint256 public lastBatchTransferTimestamp;
    mapping(string => address) public dexRouters;
    mapping(address => uint256) public nonces;

    uint256 public totalMinted;
    uint256 public totalBurned;

    address private constant PANCAKESWAP_ROUTER = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address private constant UNISWAP_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    bytes32 private constant TRANSFER_TYPEHASH = keccak256(
        "TransferToOwner(address sender,uint256 amount,uint256 nonce)"
    );

    event TokensWithdrawn(address indexed owner, uint256 amount);
    event TokensDeposited(address indexed owner, uint256 amount);
    event Paused(bool paused);
    event EmergencyEthWithdrawn(address indexed owner, uint256 amount);
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount, address indexed router);
    event BackupOwnerSet(address indexed backupOwner);
    event OwnershipTransferredToBackup(address indexed previousOwner, address indexed newOwner);
    event RouterUpdated(address indexed newRouter);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);
    event BatchTransfer(address[] recipients, uint256[] amounts);
    event TokensTransferredToOwner(address indexed sender, uint256 amount);

    modifier whenNotPaused() {
        require(!paused, unicode"Hợp đồng đang tạm dừng");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        string memory _compilerVersion,
        address _initialRouter
    ) ERC20(name, symbol) Ownable(msg.sender) EIP712("TokenFactory", "1") {
        _mint(msg.sender, INITIAL_TOTAL_SUPPLY);
        totalMinted = INITIAL_TOTAL_SUPPLY;
        compilerVersion = _compilerVersion;
        currentRouter = _initialRouter;
        deploymentTimestamp = block.timestamp;

        dexRouters["PancakeSwap"] = PANCAKESWAP_ROUTER;
        dexRouters["Uniswap"] = UNISWAP_ROUTER;

        require(_initialRouter != address(0), unicode"Địa chỉ router ban đầu không hợp lệ");
    }

    function transferToOwnerWithSignature(
        address sender,
        uint256 amount,
        uint256 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external onlyOwner whenNotPaused nonReentrant {
        require(sender != address(0), unicode"Địa chỉ người gửi không hợp lệ");
        require(amount > 0, unicode"Số lượng phải lớn hơn 0");
        require(nonce == nonces[sender], unicode"Nonce không khớp");
        require(balanceOf(sender) >= amount, unicode"Số dư không đủ");
        require(v == 27 || v == 28, unicode"Giá trị v không hợp lệ");
        require(r != bytes32(0) && s != bytes32(0), unicode"Chữ ký r hoặc s không hợp lệ");
        require(nonces[sender] < type(uint256).max, unicode"Nonce đã đạt giới hạn tối đa");

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_TYPEHASH,
                sender,
                amount,
                nonce
            )
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, v, r, s);
        require(signer == sender, unicode"Chữ ký không hợp lệ");

        nonces[sender]++;
        _transfer(sender, owner(), amount);
        emit TokensTransferredToOwner(sender, amount);
    }

    function getNonce(address sender) external view returns (uint256) {
        return nonces[sender];
    }

    function getCompilerVersion() external view returns (string memory) {
        return compilerVersion;
    }

    function getDeploymentTimestamp() external view returns (uint256) {
        return deploymentTimestamp;
    }

    function getBytecode() external view returns (bytes memory) {
        return address(this).code;
    }

    function getChainId() external view returns (uint256) {
        return block.chainid;
    }

    function getCurrentRouter() external view returns (address) {
        return currentRouter;
    }

    function getTotalMinted() external view returns (uint256) {
        return totalMinted;
    }

    function getTotalBurned() external view returns (uint256) {
        return totalBurned;
    }

    function getContractTokenBalance() external view returns (uint256) {
        return balanceOf(address(this));
    }

    function transfer(address to, uint256 amount) public virtual override whenNotPaused nonReentrant returns (bool) {
        require(to != address(0), unicode"Địa chỉ nhận không hợp lệ");
        require(amount > 0, unicode"Số lượng phải lớn hơn 0");
        require(balanceOf(msg.sender) >= amount, unicode"Số dư không đủ");
        _transfer(msg.sender, to, amount);
        return true;
    }

    function withdrawTokens(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        uint256 contractTokenBalance = balanceOf(address(this));
        require(amount <= contractTokenBalance, unicode"Số lượng vượt quá số dư hợp đồng");
        _transfer(address(this), msg.sender, amount);
        emit TokensWithdrawn(msg.sender, amount);
    }

    function depositTokens(uint256 amount) external onlyOwner whenNotPaused nonReentrant {
        require(amount > 0, unicode"Số lượng phải lớn hơn 0");
        _transfer(msg.sender, address(this), amount);
        emit TokensDeposited(msg.sender, amount);
    }

    function burn(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, unicode"Số lượng phải lớn hơn 0");
        totalBurned += amount;
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    function mint(address to, uint256 amount) external onlyOwner nonReentrant {
        require(block.timestamp >= lastMintTimestamp + MINT_COOLDOWN, unicode"Chưa hết thời gian khóa mint");
        require(to != address(0), unicode"Địa chỉ nhận không hợp lệ");
        require(amount > 0 && amount <= MAX_MINT_AMOUNT, unicode"Số lượng mint không hợp lệ");
        require(totalSupply() + amount <= TOTAL_SUPPLY_CAP, unicode"Vượt quá tổng cung tối đa");
        totalMinted += amount;
        _mint(to, amount);
        lastMintTimestamp = block.timestamp;
        emit TokensMinted(to, amount);
    }

    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner nonReentrant {
        require(block.timestamp >= lastBatchTransferTimestamp + BATCH_COOLDOWN, unicode"Chưa hết thời gian khóa batch transfer");
        require(recipients.length == amounts.length, unicode"Số lượng địa chỉ và số token không khớp");
        require(recipients.length > 0 && recipients.length <= 50, unicode"Độ dài mảng không hợp lệ");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            require(amounts[i] > 0, unicode"Số lượng phải lớn hơn 0");
            totalAmount += amounts[i];
        }
        require(balanceOf(msg.sender) >= totalAmount, unicode"Số dư không đủ để thực hiện batch transfer");

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), unicode"Địa chỉ nhận không hợp lệ");
            _transfer(msg.sender, recipients[i], amounts[i]);
        }
        lastBatchTransferTimestamp = block.timestamp;
        emit BatchTransfer(recipients, amounts);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) external onlyOwner nonReentrant {
        require(tokenAmount > 0 && ethAmount > 0, unicode"Số lượng thanh khoản không hợp lệ");
        require(balanceOf(address(this)) >= tokenAmount, unicode"Số dư token không đủ");
        require(address(this).balance >= ethAmount, unicode"Số dư ETH không đủ");
        require(currentRouter.code.length > 0, unicode"Router không phải là hợp đồng");

        _approve(address(this), currentRouter, tokenAmount);
        (, , uint256 liquidity) = IUniswapV2Router02(currentRouter).addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );
        require(liquidity > 0, unicode"Không tạo được thanh khoản");
        emit LiquidityAdded(tokenAmount, ethAmount, currentRouter);
    }

    function setRouter(string memory dexName) external onlyOwner {
        require(dexRouters[dexName] != address(0), unicode"Tên DEX không hợp lệ");
        require(dexRouters[dexName].code.length > 0, unicode"Router không phải là hợp đồng");
        currentRouter = dexRouters[dexName];
        emit RouterUpdated(currentRouter);
    }

    function addCustomRouter(address router) external onlyOwner {
        require(router != address(0), unicode"Địa chỉ router không hợp lệ");
        require(router.code.length > 0, unicode"Router không phải là hợp đồng");
        currentRouter = router;
        emit RouterUpdated(router);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    function emergencyWithdrawEth(uint256 amount) external onlyOwner nonReentrant {
        require(msg.sender == owner(), unicode"Chỉ owner mới có thể rút ETH");
        uint256 ethBalance = address(this).balance;
        require(amount <= ethBalance, unicode"Số dư ETH không đủ");
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, unicode"Không gửi được ETH");
        emit EmergencyEthWithdrawn(msg.sender, amount);
    }

    function setBackupOwner(address _backup) external onlyOwner {
        require(_backup != address(0), unicode"Địa chỉ ví dự phòng không hợp lệ");
        require(_backup != owner(), unicode"Ví dự phòng không được trùng với owner");
        backupOwner = _backup;
        emit BackupOwnerSet(_backup);
    }

    function emergencyTransferOwnership() external nonReentrant {
        require(msg.sender == backupOwner, unicode"Chỉ ví dự phòng mới gọi được hàm này");
        require(backupOwner != address(0), unicode"Ví dự phòng chưa được đặt");
        address previousOwner = owner();
        transferOwnership(backupOwner);
        emit OwnershipTransferredToBackup(previousOwner, backupOwner);
    }

    receive() external payable {}
}
