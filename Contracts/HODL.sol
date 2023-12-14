/**
 *  SPDX-License-Identifier: MIT
 */

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./IGame.sol";
import "./IBank.sol";

/**
 *  dex pancake interface
 */

interface IFactory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IRouter {
    function WETH() external pure returns (address);

    function factory() external pure returns (address);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);
}

interface IPair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IRouter02 is IRouter {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract HODL is Context, IERC20, IERC20Metadata, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    // a mapping from an address to whether or not it can mint / burn
    mapping(address => bool) controllers;

    uint256 private _totalSupply;
    string private _name = "HODL";
    string private _symbol = "HODL";
    // uint256 private _initSupply = 100000000 * 10**18;

    uint256 public dexTaxFee = 100; //take fee while sell token to dex
    address public taxAddress;

    // IBank public bank;

    address public bank;
    address public game;
    address public treasury;
    address public Avault;
    address public Uvault;
    address public Hvault;
    address public marketing;
    address public team;
    address public pairAddress;
    // address public routerAddress = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
    address public routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public usdc = 0xc7AD46e0b8a400Bb3C915120d284AafbA8fc4735;

    bool public gradualFee = true;

    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => uint256) public swapIntensity;
    mapping(address => uint256) public lastSwapTimestamp;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */

    constructor() {
        // _mint(msg.sender, _initSupply);

        taxAddress = address(0x85eE68703D80Fe7958C146BB61623c3163E458E9);

        IRouter _router = IRouter02(routerAddress);

        pairAddress = IFactory(_router.factory()).createPair(
            address(this),
            address(usdc)
            // _router.WETH()
        );

        // set the rest of the contract variables
        routerAddress = address(_router);

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
    }

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function setTaxAddress(address _taxAddress) public onlyOwner {
        taxAddress = _taxAddress;
    }

    function setTax(uint256 _taxFee) public onlyOwner {
        dexTaxFee = _taxFee;
    }

    function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function amountForEth(uint256 ethAmount)
        public
        view
        returns (uint256 tokenAmount)
    {
        address _token0Address = IPair(pairAddress).token0();
        address wethAddress = IRouter(routerAddress).WETH();

        (uint112 _reserve0, uint112 _reserve1, ) = IPair(pairAddress)
            .getReserves();
        uint256 _tokenAmount;
        uint256 _wethAmount;
        if (_token0Address == wethAddress) {
            _wethAmount = _reserve0;
            _tokenAmount = _reserve1;
        } else {
            _wethAmount = _reserve1;
            _tokenAmount = _reserve0;
        }
        tokenAmount = ethAmount.mul(_tokenAmount).div(_wethAmount);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(
                _msgSender(),
                spender,
                currentAllowance.sub(subtractedValue)
            );
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        bool holdNFT = false;
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        unchecked {
            _balances[sender] = senderBalance.sub(amount);
        }

        bool takeFee = true;
        if (_isExcludedFromFee[sender]) {
            takeFee = false;
        }

        // if (sender != address(routerAddress)) holdNFT = isHolder(sender);

        if (recipient == pairAddress && takeFee) {
            uint256 feesMul = 10;

            // if (isHolder(sender)) feesMul = calculateTax(amount);
            if (gradualFee) feesMul = calculateTax(amount);
            console.log("!!!!!!!!!! coef :", feesMul);

            uint256 taxFee = amount.mul(feesMul).div(100);

            swapAndDispatchTax1(sender, taxFee, feesMul);
            amount = amount.sub(taxFee);
        }
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function calculateTax(uint256 amount) internal returns (uint256 coef) {
        uint256 lastTime = lastSwapTimestamp[msg.sender];

        console.log("!!!!!!!!!! lastTime :", lastTime);

        if (lastTime + 1 days < block.timestamp) {
            swapIntensity[msg.sender] = amount;
        } else {
            swapIntensity[msg.sender] += amount;
        }

        uint256 mul = swapIntensity[msg.sender];

        console.log("!!!!!!!!!! mul :", mul);

        lastSwapTimestamp[msg.sender] = block.timestamp;

        if (mul <= 100 ether) coef = 10;
        else if (mul <= 200 ether) coef = 20;
        else if (mul <= 300 ether) coef = 30;
        else if (mul <= 400 ether) coef = 40;
        else coef = 50;
    }

    function swapAndDispatchTax1(
        address sender,
        uint256 amount,
        uint256 feesMul
    ) internal {
        uint256 taxtreasury;
        uint256 taxAvault;
        uint256 taxUvault;
        uint256 taxHvault;
        uint256 taxmarketing;
        uint256 taxteam;

        if (feesMul == 10) {
            taxtreasury = amount.mul(20).div(100);
            taxAvault = amount.mul(20).div(100);
            taxUvault = amount.mul(20).div(100);
            // taxHvault = amount.mul(0).div(100);
            taxmarketing = amount.mul(20).div(100);
            taxteam = amount.mul(20).div(100);
        } else {
            taxtreasury = amount.mul(20).div(100);
            taxAvault = amount.mul(20).div(100);
            taxUvault = amount.mul(20).div(100);
            // taxHvault = amount.mul(0).div(100);
            taxmarketing = amount.mul(20).div(1000);
            taxteam = amount.mul(20).div(1000);
        }
        // if (feesMul == 10) {
        //     taxtreasury = amount.mul(20).div(100);
        //     taxAvault = amount.mul(25).div(100);
        //     taxUvault = amount.mul(25).div(100);
        //     // taxHvault = amount.mul(0).div(100);
        //     taxmarketing = amount.mul(15).div(100);
        //     taxteam = amount.mul(15).div(100);
        // } else {
        //     taxtreasury = amount.mul(35).div(100);
        //     taxAvault = amount.mul(10).div(100);
        //     taxUvault = amount.mul(10).div(100);
        //     // taxHvault = amount.mul(0).div(100);
        //     taxmarketing = amount.mul(75).div(1000);
        //     taxteam = amount.mul(75).div(1000);
        // }

        sendToTreasury(sender, taxtreasury);
        sendToAvault(sender, taxAvault);
        sendToUvault(sender, taxUvault);
        sendToHvault(sender, taxHvault);
        sendToMWallet(sender, taxmarketing);
        sendToTWallet(sender, taxteam);
    }

    function swapAndDispatchTax2(address sender, uint256 amount) internal {
        uint256 taxtreasury = amount.mul(35).div(100);
        uint256 taxAvault = amount.mul(10).div(100);
        uint256 taxUvault = amount.mul(10).div(100);
        uint256 taxHvault = amount.mul(35).div(100);
        uint256 taxmarketing = amount.mul(10).div(100);
        uint256 taxteam = amount.mul(0).div(100);

        sendToTreasury(sender, taxtreasury);
        sendToAvault(sender, taxAvault);
        sendToUvault(sender, taxUvault);
        sendToHvault(sender, taxHvault);
        sendToMWallet(sender, taxmarketing);
        sendToTWallet(sender, taxteam);
    }

    function sendToUvault(address sender, uint256 amount) internal {
        swaper(amount, address(Uvault));
    }

    function sendToMWallet(address sender, uint256 amount) internal {
        swaper(amount, address(marketing));
        emit Transfer(sender, marketing, amount);
    }

    function sendToTWallet(address sender, uint256 amount) internal {
        swaper(amount, address(team));
        emit Transfer(sender, team, amount);
    }

    function sendToAvault(address sender, uint256 amount) internal {
        swaper(amount, address(Avault));
        emit Transfer(sender, Avault, amount);
    }

    function sendToTreasury(address sender, uint256 amount) internal {
        _balances[treasury] = _balances[treasury].add(amount);
        emit Transfer(sender, treasury, amount);
    }

    function sendToHvault(address sender, uint256 amount) internal {
        _balances[Hvault] = _balances[Hvault].add(amount);
        emit Transfer(sender, Hvault, amount);
    }

    function swaper(uint256 amount, address to) internal {
        uint256 UBalance = IERC20(address(this)).balanceOf(address(this));
        if (UBalance >= 1 ether && amount > 1000000) {
            swapTokensForUSDC(amount, address(to));
        } else {
            _balances[address(this)] = _balances[address(this)].add(amount);
        }
    }

    function swapTokensForUSDC(uint256 tokenAmount, address to) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(usdc);
        // path[1] = IRouter02(routerAddress).WETH();

        _approve(address(this), address(routerAddress), tokenAmount);

        // make the swap
        IRouter02(routerAddress)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0, // accept any amount of ETH
                path,
                address(to),
                block.timestamp
            );

        // _approve(address(this), address(pairAddress), tokenAmount);

        // IPair(pairAddress).swap(
        //     tokenAmount,
        //     0, // accept any amount of ETH
        //     address(this),
        //     ""
        // );
    }

    function swapUSDCForAvax(uint256 ethAmount) internal {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = IRouter(routerAddress).WETH();
        path[1] = address(usdc);

        IERC20(IRouter(routerAddress).WETH()).approve(
            address(routerAddress),
            ethAmount
        );

        // make the swap
        uint256[] memory amounts = IRouter02(routerAddress)
            .swapExactETHForTokens{value: ethAmount}(
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    receive() external payable {}

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * mints $HODL to a recipient
     * @param to the recipient of the $HODL
     * @param amount the amount of $HODL to mint
     */
    function mint(address to, uint256 amount) external {
        require(controllers[msg.sender], "Only controllers can mint");
        _mint(to, amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function isHolder(address user) public view returns (bool) {
        uint256 gameBalance = IGame(game).balanceHolder(user);
        uint256 bankBalance = IBank(bank).counterByWallet(user);
        if (gameBalance > 0) return true;
        if (bankBalance > 0) return true;
        return false;
    }

    /**
     * enables an address to mint / burn
     * @param controller the address to enable
     */
    function addController(address controller) external onlyOwner {
        controllers[controller] = true;
    }

    function setTreasury(address _treasury) public onlyOwner {
        treasury = _treasury;
    }

    function setAvault(address _Avault) public onlyOwner {
        Avault = _Avault;
    }

    function setUvault(address _Uvault) public onlyOwner {
        Uvault = _Uvault;
    }

    function setHvault(address _Hvault) public onlyOwner {
        Hvault = _Hvault;
    }

    function setmarketing(address _marketing) public onlyOwner {
        marketing = _marketing;
    }

    function setteam(address _team) public onlyOwner {
        team = _team;
    }

    function setGame(address _game) public onlyOwner {
        game = _game;
    }

    function setBank(address _bank) public onlyOwner {
        bank = _bank;
    }

    function setGradualFee(bool _vote) public onlyOwner {
        gradualFee = _vote;
    }

    /**
     * disables an address from minting / burning
     * @param controller the address to disbale
     */
    function removeController(address controller) external onlyOwner {
        controllers[controller] = false;
    }

    function withdrawAnyToken(
        address _recipient,
        address _ERC20address,
        uint256 _amount
    ) public onlyOwner returns (bool) {
        IERC20(_ERC20address).transfer(_recipient, _amount); //use of the _ERC20 traditional transfer
        return true;
    }
}
