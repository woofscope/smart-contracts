// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Factory.sol";

contract AdvancedToken is IERC20, Pausable, Ownable, EIP712, ReentrancyGuard {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public blacklisted;
    mapping(address => bool) public isExcluded;
    mapping(address => uint256) public lastTransactionTime;

    uint256 private _totalSupply;
    uint256 public maxSupply;
    bool public immutable mintable;
    bool public immutable pausable;
    uint256 public cooldownTime;
    uint256 public maxWalletBalance;
    uint256 public maxTransactionAmount;
    bool public tradingEnabled;
    bool public limitsEnabled;
    bool public antbot;
    
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public constant BASE_DEPLOYMENT_FEE = 0.01 ether;
    uint256 public constant FEATURE_FEE = 0.05 ether;
    address public constant FEE_WALLET = 0x1BfA43fF53c667bed28231b404d025D50f1488F6;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    bool public inSwap;
    
    event LiquidityAdded(uint256 tokenAmount, uint256 ethAmount);
    event ExcludedFromRestrictions(address indexed account, bool excluded);
    event Blacklisted(address indexed account, bool status);
    event TradingEnabled(bool enabled);
    event CooldownTimeConfig(uint256 amount);
    event LimitsEnabled(bool enabled);
    event MaxWalletBalanceUpdated(uint256 newMaxWalletBalance);
    event MaxTransactionAmountUpdated(uint256 newMaxTransactionAmount);
    
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    modifier whenTradingEnabled() {
        require(tradingEnabled || isExcluded[_msgSender()], "Trading not enabled");
        _;
    }

    struct TokenConfig {
        string name;
        string symbol;
        uint8 decimals;
        uint256 initialSupply;
        uint256 maxSupply;
        bool mintable;
        bool pausable;
        bool limits;
        bool antbot;
        uint256 cooldownTime;
        uint256 maxWalletBalance;
        uint256 maxTransactionAmount;
        bool enableTrading;
        address routerAddress;
    }

    function calculateDeploymentFee(bool _mintable, bool _pausable, bool _limitsEnabled, bool _antbot) public pure returns (uint256) {
        uint256 totalFee = BASE_DEPLOYMENT_FEE;
        
        if (_mintable) totalFee += FEATURE_FEE;
        if (_pausable) totalFee += FEATURE_FEE;
        if (_antbot) totalFee += FEATURE_FEE;
        if (_limitsEnabled) totalFee += FEATURE_FEE;
        
        return totalFee;
    }

    constructor(TokenConfig memory config) 
        payable
        EIP712(config.name, "1")
    {
        uint256 requiredFee = calculateDeploymentFee(config.mintable, config.pausable, config.limits, config.antbot);
        require(msg.value >= requiredFee, "Insufficient deployment fee");
        
        _name = config.name;
        _symbol = config.symbol;
        _decimals = config.decimals;
        maxSupply = config.maxSupply * 10**_decimals;
        mintable = config.mintable;
        pausable = config.pausable;
        cooldownTime = config.cooldownTime;
        maxWalletBalance = config.maxWalletBalance;
        maxTransactionAmount = config.maxTransactionAmount;
        tradingEnabled = config.enableTrading;
        limitsEnabled = config.limits;
        antbot = config.antbot;

        uint256 initialSupply = config.initialSupply * 10**_decimals;
        require(initialSupply <= maxSupply, "Initial supply exceeds max supply");
        
        _mint(_msgSender(), initialSupply);

        (bool sent, ) = payable(FEE_WALLET).call{value: msg.value}("");
        require(sent, "Failed to send deployment fee");

        if (config.routerAddress != address(0)) {
            uniswapV2Router = IUniswapV2Router02(config.routerAddress);
            uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
                .createPair(address(this), uniswapV2Router.WETH());
            
            isExcluded[uniswapV2Pair] = true;
            emit ExcludedFromRestrictions(uniswapV2Pair, true);
        }
    }

    // ERC20 Standard Functions
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

    function transfer(address to, uint256 amount) public override whenNotPaused whenTradingEnabled returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused whenTradingEnabled returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // Internal Functions
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(!blacklisted[from] && !blacklisted[to], "Address is blacklisted");

        if (limitsEnabled && !isExcluded[from] && !isExcluded[to]) {
            require(amount <= maxTransactionAmount, "Amount exceeds max transaction");
            require(_balances[to] + amount <= maxWalletBalance, "Exceeds max wallet balance");
        }
        if(antbot && !isExcluded[from] && !isExcluded[to]){
            require(block.timestamp >= lastTransactionTime[from] + cooldownTime, "Cooldown period active");
            lastTransactionTime[from] = block.timestamp;
        }

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to zero address");
        require(_totalSupply + amount <= maxSupply, "Exceeds max supply");

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero address");
        require(spender != address(0), "Approve to zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    // Owner Functions
    function mint(address to, uint256 amount) external onlyOwner {
        require(mintable, "Minting is disabled");
        _mint(to, amount);
    }

    function setBlacklist(address account, bool status) external onlyOwner {
        require(account != owner(), "Cannot blacklist owner");
        blacklisted[account] = status;
        emit Blacklisted(account, status);
    }

    function setExcluded(address account, bool status) external onlyOwner {
        isExcluded[account] = status;
        emit ExcludedFromRestrictions(account, status);
    }

    function setTradingEnabled(bool enabled) external onlyOwner {
        tradingEnabled = enabled;
        emit TradingEnabled(enabled);
    }

    function setCooldownTime(uint256 amount) external onlyOwner {
        cooldownTime = amount;
        emit CooldownTimeConfig(amount)
    }

    function setLimitsEnabled(bool enabled) external onlyOwner {
        limitsEnabled = enabled;
        emit LimitsEnabled(enabled);
    }

    function setMaxWalletBalance(uint256 amount) external onlyOwner {
        maxWalletBalance = amount;
        emit MaxWalletBalanceUpdated(amount);
    }

    function setMaxTransactionAmount(uint256 amount) external onlyOwner {
        maxTransactionAmount = amount;
        emit MaxTransactionAmountUpdated(amount);
    }

    function pause() external onlyOwner {
        require(pausable, "Pausable feature not enabled");
        _pause();
    }

    function unpause() external onlyOwner {
        require(pausable, "Pausable feature not enabled");
        _unpause();
    }

    // Liquidity Functions
    function addLiquidity(uint256 tokenAmount) external payable onlyOwner lockTheSwap {
        require(address(uniswapV2Router) != address(0), "Router not set");
        require(tokenAmount > 0 && msg.value > 0, "Invalid amounts");

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            tokenAmount,
            0,
            0,
            owner(),
            block.timestamp
        );

        emit LiquidityAdded(tokenAmount, msg.value);
    }

    receive() external payable {}
}