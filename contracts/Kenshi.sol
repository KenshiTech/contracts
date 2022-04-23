//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

/*
  @source https://github.com/binance-chain/bsc-genesis-contract/blob/master/contracts/bep20_template/BEP20Token.template

  CHANGES:
  
  - formatted with Prettier.
  - Updated syntax to 0.8.10
*/

import "./interfaces/IBEP20.sol";
import "./interfaces/IBEP165.sol";
import "./interfaces/IBEP1363.sol";
import "./interfaces/IBEP1363Receiver.sol";
import "./interfaces/IBEP1363Spender.sol";

import "./libraries/Address.sol";

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() {}

    function _msgSender() internal view returns (address) {
        return msg.sender;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Kenshi is Context, IBEP20, IBEP165, IBEP1363, Ownable {
    using Address for address;
    /* BEP20 related */

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint8 private _decimals;

    string private _symbol;
    string private _name;

    /* Kenshi related */

    /* Reward calculation */

    uint256 private _totalExcluded;
    uint256 private _circulation;
    uint256 private _balanceCoeff;
    uint256 private _minBalanceCoeff;

    /* Treasury */

    address private _treasuryAddr;

    /* Special addresses (lockers, reserve, liquidity pools...) */

    mapping(address => bool) private _excludedFromTax;
    mapping(address => bool) private _excludedFromFines;
    mapping(address => bool) private _excludedFromReflects;
    mapping(address => bool) private _excludedFromMaxBalance;

    /**
     * Admins can exclude or include addresses from tax, reflections or
     * maximum balance. An example is a Deployer creating a Kenshi Locker.
     */

    mapping(address => bool) private _adminAddrs;

    /* Tokenomics */

    mapping(address => uint256) private _purchaseTimes;

    address private _burnAddr;

    uint8 private _baseTax;
    uint8 private _burnPercentage;
    uint8 private _investPercentage;

    uint256 private _minMaxBalance;
    uint256 private _burnThreshold;

    /**
     * Instead of implementing log functions and calculating the fine
     * amount on-demand, we decided to use pre-calculated values for it.
     * Just a bit less accurate, but saves a lot of gas.
     */
    uint8[30] private _earlySaleFines = [
        49,
        39,
        33,
        29,
        26,
        23,
        21,
        19,
        17,
        16,
        14,
        13,
        12,
        11,
        10,
        9,
        8,
        7,
        7,
        6,
        5,
        4,
        4,
        3,
        3,
        2,
        2,
        1,
        0,
        0
    ];

    /* Security / Anti-bot measures */

    bool private _tradeOpen;

    constructor() {
        _name = "Kenshi";
        _symbol = "KENSHI";

        /**
         * Large supply and large decimal places are to help with
         * the accuracy loss caused by the reward system.
         */

        _decimals = 18;
        _totalSupply = 10e12 * 1e18;
        _balances[msg.sender] = _totalSupply;

        emit Transfer(address(0), msg.sender, _totalSupply);

        /* Kenshi related */

        _baseTax = 5;
        _burnPercentage = 1;
        _investPercentage = 50;

        /* Give the required privileges to the owner */

        _adminAddrs[msg.sender] = true;
        _excludedFromTax[msg.sender] = true;
        _excludedFromFines[msg.sender] = true;
        _excludedFromReflects[msg.sender] = true;
        _excludedFromMaxBalance[msg.sender] = true;

        /* Burning */

        _burnAddr = address(0xdead);
        _burnThreshold = _totalSupply / 2;

        _excludedFromTax[_burnAddr] = true;
        _excludedFromReflects[_burnAddr] = true;
        _excludedFromMaxBalance[_burnAddr] = true;

        /* Treasury */

        _treasuryAddr = address(0);

        /* Set initial max balance, this amount increases over time */

        _minMaxBalance = _totalSupply / 100;

        /**
         * This value gives us maximum precision without facing overflows
         * or underflows. Be careful when updating the _totalSupply or
         * the value below.
         */

        _balanceCoeff = (~uint256(0)) / _totalSupply;
        _minBalanceCoeff = 1e18;

        /* Other initial variable values */

        _totalExcluded = _totalSupply;
    }

    /**
     * @dev Throws if called by any account other than the admins.
     */
    modifier onlyAdmins() {
        require(_adminAddrs[_msgSender()], "Kenshi: Caller is not an admin");
        _;
    }

    /**
     * @dev Returns the bep token owner.
     */
    function getOwner() external view returns (address) {
        return owner();
    }

    /**
     * @dev Returns the token decimals.
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the token symbol.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the token name.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * @dev See {BEP20-totalSupply}.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {BEP20-balanceOf}.
     */
    function balanceOf(address account) public view returns (uint256) {
        if (isExcluded(account)) {
            return _balances[account];
        }
        return _balances[account] / _balanceCoeff;
    }

    /**
     * @dev See {BEP20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {BEP20-allowance}.
     */
    function allowance(address addr, address spender)
        external
        view
        returns (uint256)
    {
        return _allowances[addr][spender];
    }

    /**
     * @dev See {BEP20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {BEP20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {BEP20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(
            _allowances[sender][_msgSender()] > amount,
            "BEP20: transfer amount exceeds allowance"
        );
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {BEP20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {BEP20-approve}.
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
        external
        returns (bool)
    {
        require(
            _allowances[_msgSender()][spender] > subtractedValue,
            "BEP20: decreased allowance below zero"
        );
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    event Reflect(uint256 amount);

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     * Emits a {Reflect} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - `amount` should not exceed the maximum allowed
     * - `amount` should not cause the recipient balance
                  to get bigger than the maximum allowed
       - trading should be open
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "Kenshi: Transfer amount should be bigger than 0");

        if (
            (isTaxless(sender) && isFineFree(sender)) ||
            (isTaxless(recipient) && isFineFree(recipient))
        ) {
            uint256 rOutgoing = _getTransferAmount(sender, amount);
            uint256 rIncoming = _getTransferAmount(recipient, amount);

            require(
                rOutgoing <= _balances[sender],
                "Kenshi: Balance is lower than the requested amount"
            );

            /* Required for making a liquidity pool */
            if (_tradeOpen || sender != owner()) {
                require(
                    _checkMaxBalance(recipient, rIncoming),
                    "Kenshi: Resulting balance more than the maximum allowed"
                );
            }

            _balances[sender] = _balances[sender] - rOutgoing;
            _balances[recipient] = _balances[recipient] + rIncoming;

            if (isExcluded(sender) && !isExcluded(recipient)) {
                _totalExcluded = _totalExcluded - amount;
            } else if (!isExcluded(sender) && isExcluded(recipient)) {
                _totalExcluded = _totalExcluded + amount;
            }

            emit Transfer(sender, recipient, amount);

            return;
        }

        require(_tradeOpen, "Kenshi: Trading is not open yet");

        uint256 burn = _getBurnAmount(amount);
        uint256 tax = _getTax(sender, amount) - burn;

        /* Split the tax */

        uint256 invest = (tax * _investPercentage) / 100;
        uint256 reward = tax - invest;

        uint256 remainingAmount = amount - tax - burn;
        uint256 outgoing = _getTransferAmount(sender, amount);
        uint256 incoming = _getTransferAmount(recipient, remainingAmount);

        require(
            outgoing <= _balances[sender],
            "Kenshi: Balance is lower than the requested amount"
        );

        require(
            _checkMaxBalance(recipient, incoming),
            "Kenshi: Resulting balance more than the maximum allowed"
        );

        if (_treasuryAddr != address(0)) {
            _balances[_treasuryAddr] = _balances[_treasuryAddr] + invest;
            _totalExcluded = _totalExcluded + invest;
            emit Transfer(sender, _treasuryAddr, invest);
        } else {
            reward = reward + invest;
        }

        if (burn > 0) {
            _balances[_burnAddr] = _balances[_burnAddr] + burn;
            _totalExcluded = _totalExcluded + burn;
            emit Transfer(sender, _burnAddr, burn);
        }

        _balances[sender] = _balances[sender] - outgoing;
        _balances[recipient] = _balances[recipient] + incoming;

        emit Transfer(sender, recipient, remainingAmount);

        if (isExcluded(sender)) {
            _totalExcluded = _totalExcluded - amount;
        }

        if (isExcluded(recipient)) {
            _totalExcluded = _totalExcluded + remainingAmount;
        }

        _circulation = _totalSupply - _totalExcluded;
        uint256 delta = (_balanceCoeff * reward) / _circulation;
        bool shoudReflect = _balanceCoeff - delta > _minBalanceCoeff;

        if (!shoudReflect && _treasuryAddr != address(0)) {
            _balances[_treasuryAddr] = _balances[_treasuryAddr] + reward;
            _totalExcluded = _totalExcluded + reward;
            emit Transfer(sender, _treasuryAddr, reward);
        } else if (shoudReflect && delta < _balanceCoeff) {
            _balanceCoeff = _balanceCoeff - delta;
            emit Reflect(reward);
        } else {
            _balances[_burnAddr] = _balances[_burnAddr] + reward;
            _totalExcluded = _totalExcluded + reward;
            emit Transfer(sender, _burnAddr, reward);
        }

        _recordPurchase(recipient, incoming);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `addr`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `addr` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address addr,
        address spender,
        uint256 amount
    ) internal {
        require(addr != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[addr][spender] = amount;
        emit Approval(addr, spender, amount);
    }

    /* ERC165 methods */

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IBEP1363).interfaceId;
    }

    /* BEP1363 methods */

    /**
     * @dev Transfer tokens to a specified address and then execute a callback on recipient.
     * @param recipient The address to transfer to.
     * @param amount The amount to be transferred.
     * @return A boolean that indicates if the operation was successful.
     */
    function transferAndCall(address recipient, uint256 amount)
        public
        returns (bool)
    {
        return transferAndCall(recipient, amount, "");
    }

    /**
     * @dev Transfer tokens to a specified address and then execute a callback on recipient.
     * @param recipient The address to transfer to
     * @param amount The amount to be transferred
     * @param data Additional data with no specified format
     * @return A boolean that indicates if the operation was successful.
     */
    function transferAndCall(
        address recipient,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        transfer(recipient, amount);
        require(
            _checkAndCallTransfer(_msgSender(), recipient, amount, data),
            "BEP1363: _checkAndCallTransfer reverts"
        );
        return true;
    }

    /**
     * @dev Transfer tokens from one address to another and then execute a callback on recipient.
     * @param sender The address which you want to send tokens from
     * @param recipient The address which you want to transfer to
     * @param amount The amount of tokens to be transferred
     * @return A boolean that indicates if the operation was successful.
     */
    function transferFromAndCall(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        return transferFromAndCall(sender, recipient, amount, "");
    }

    /**
     * @dev Transfer tokens from one address to another and then execute a callback on recipient.
     * @param sender The address which you want to send tokens from
     * @param recipient The address which you want to transfer to
     * @param amount The amount of tokens to be transferred
     * @param data Additional data with no specified format
     * @return A boolean that indicates if the operation was successful.
     */
    function transferFromAndCall(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        transferFrom(sender, recipient, amount);
        require(
            _checkAndCallTransfer(sender, recipient, amount, data),
            "BEP1363: _checkAndCallTransfer reverts"
        );
        return true;
    }

    /**
     * @dev Approve spender to transfer tokens and then execute a callback on recipient.
     * @param spender The address allowed to transfer to
     * @param amount The amount allowed to be transferred
     * @return A boolean that indicates if the operation was successful.
     */
    function approveAndCall(address spender, uint256 amount)
        public
        returns (bool)
    {
        return approveAndCall(spender, amount, "");
    }

    /**
     * @dev Approve spender to transfer tokens and then execute a callback on recipient.
     * @param spender The address allowed to transfer to.
     * @param amount The amount allowed to be transferred.
     * @param data Additional data with no specified format.
     * @return A boolean that indicates if the operation was successful.
     */
    function approveAndCall(
        address spender,
        uint256 amount,
        bytes memory data
    ) public returns (bool) {
        approve(spender, amount);
        require(
            _checkAndCallApprove(spender, amount, data),
            "BEP1363: _checkAndCallApprove reverts"
        );
        return true;
    }

    /**
     * @dev Internal function to invoke `onTransferReceived` on a target address
     *  The call is not executed if the target address is not a contract
     * @param sender address Representing the previous owner of the given token value
     * @param recipient address Target address that will receive the tokens
     * @param amount uint256 The amount mount of tokens to be transferred
     * @param data bytes Optional data to send along with the call
     * @return whether the call correctly returned the expected magic value
     */
    function _checkAndCallTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory data
    ) internal returns (bool) {
        if (!recipient.isContract()) {
            return false;
        }
        bytes4 retval = IBEP1363Receiver(recipient).onTransferReceived(
            _msgSender(),
            sender,
            amount,
            data
        );
        return (retval ==
            IBEP1363Receiver(recipient).onTransferReceived.selector);
    }

    /**
     * @dev Internal function to invoke `onApprovalReceived` on a target address
     *  The call is not executed if the target address is not a contract
     * @param spender address The address which will spend the funds
     * @param amount uint256 The amount of tokens to be spent
     * @param data bytes Optional data to send along with the call
     * @return whether the call correctly returned the expected magic value
     */
    function _checkAndCallApprove(
        address spender,
        uint256 amount,
        bytes memory data
    ) internal returns (bool) {
        if (!spender.isContract()) {
            return false;
        }
        bytes4 retval = IBEP1363Spender(spender).onApprovalReceived(
            _msgSender(),
            amount,
            data
        );
        return (retval == IBEP1363Spender(spender).onApprovalReceived.selector);
    }

    /* Kenshi methods */

    /**
     * @dev Records weighted purchase times for fine calculation.
     */
    function _recordPurchase(address addr, uint256 amount) private {
        uint256 current = _purchaseTimes[addr] *
            _decoeff(addr, _balances[addr] - amount);

        _purchaseTimes[addr] =
            (current + block.timestamp * _decoeff(addr, amount)) /
            balanceOf(addr);
    }

    /**
     * @dev Removes the coefficient factor from `addr` is not excluded.
     */
    function _decoeff(address addr, uint256 amount)
        private
        view
        returns (uint256)
    {
        if (isExcluded(addr)) {
            return amount;
        }
        return amount / _balanceCoeff;
    }

    /**
     * @dev Check if `addr` is excluded from tax.
     */
    function isTaxless(address addr) public view returns (bool) {
        return _excludedFromTax[addr];
    }

    /**
     * @dev Set `addr` is excluded from tax to `state`.
     */
    function setIsTaxless(address addr, bool state) external onlyAdmins {
        _excludedFromTax[addr] = state;
    }

    /**
     * @dev Check if `addr` is excluded from fines.
     */
    function isFineFree(address addr) public view returns (bool) {
        return _excludedFromFines[addr];
    }

    /**
     * @dev Set `addr` is excluded from fines to `state`.
     */
    function setIsFineFree(address addr, bool state) external onlyAdmins {
        _excludedFromFines[addr] = state;
    }

    /**
     * @dev Check if `addr` is excluded from reflects.
     */
    function isExcluded(address addr) public view returns (bool) {
        return _excludedFromReflects[addr];
    }

    /**
     * @dev Set `addr` is excluded from reflections to `state`.
     */
    function setIsExcluded(address addr, bool state) external onlyAdmins {
        if (isExcluded(addr) && !state) {
            uint256 balance = _balances[addr];
            _totalExcluded = _totalExcluded - balance;
            _balances[addr] = _balances[addr] * _balanceCoeff;
        } else if (!isExcluded(addr) && state) {
            uint256 balance = _balances[addr] / _balanceCoeff;
            _totalExcluded = _totalExcluded + balance;
            _balances[addr] = balance;
        }

        _excludedFromReflects[addr] = state;
    }

    /**
     * @dev Check if `addr` is excluded from max balance limit.
     */
    function isLimitless(address addr) public view returns (bool) {
        return _excludedFromMaxBalance[addr];
    }

    /**
     * @dev Set `addr` is excluded from max balance to `state`.
     */
    function setIsLimitless(address addr, bool state) external onlyAdmins {
        _excludedFromMaxBalance[addr] = state;
    }

    /**
     * @dev Check if `addr` is an admin.
     */
    function isAdmin(address addr) external view returns (bool) {
        return _adminAddrs[addr];
    }

    /**
     * @dev Set `addr` is excluded from reflections to `state`.
     */
    function setIsAdmin(address addr, bool state) external onlyAdmins {
        _adminAddrs[addr] = state;
    }

    /**
     * @dev Calculates the burn amount for a transaction.
     *
     * Checks how many tokens are already burned, if it's more than the
     * burn threshold then it returns zero, otherwise returns one percent
     * of `amount`.
     */
    function _getBurnAmount(uint256 amount) private view returns (uint256) {
        uint256 _burnedAmount = _balances[_burnAddr];
        if (_burnedAmount >= _burnThreshold) {
            return 0;
        }
        uint256 toBurn = amount / 100;
        if (_burnThreshold - _burnedAmount < toBurn) {
            return _burnThreshold - _burnedAmount;
        }
        return toBurn;
    }

    /**
     * @dev Check how many tokens are currently burned.
     */
    function getTotalBurned() external view returns (uint256) {
        return _balances[_burnAddr];
    }

    /**
     * @dev Check how many tokens are currently excluded.
     */
    function getTotalExcluded() external view returns (uint256) {
        return _totalExcluded;
    }

    /**
     * @dev Check how many tokens are in circulation.
     */
    function getCirculation() external view returns (uint256) {
        return _circulation;
    }

    /**
     * @dev Get tax amount for `amount` moved from `sender`.
     */
    function _getTax(address sender, uint256 amount)
        private
        view
        returns (uint256)
    {
        uint8 taxPercentage = _getTaxPercentage(sender);
        uint256 tax = (amount * taxPercentage) / 100;
        return tax;
    }

    /**
     * @dev calculate tax percentage for `sender` based on purchase times.
     */
    function _getTaxPercentage(address sender) private view returns (uint8) {
        return getTaxPercentageAt(sender, block.timestamp);
    }

    /**
     * @dev calculate tax percentage for `sender` at `timestamp` based on purchase times.
     */
    function getTaxPercentageAt(address sender, uint256 timestamp)
        public
        view
        returns (uint8)
    {
        bool taxFree = isTaxless(sender);
        bool fineFree = isFineFree(sender);
        if (taxFree && fineFree) {
            return 0;
        }
        if (fineFree) {
            return _baseTax;
        }
        uint256 daysPassed = (timestamp - _purchaseTimes[sender]) / 86400;
        if (daysPassed >= 30) {
            return taxFree ? 0 : _baseTax;
        }
        return
            taxFree
                ? _earlySaleFines[daysPassed]
                : _baseTax + _earlySaleFines[daysPassed];
    }

    /**
     * @dev Calculates transfer amount based on reward exclusion and reward coeff.
     */
    function _getTransferAmount(address sender, uint256 amount)
        private
        view
        returns (uint256)
    {
        if (isExcluded(sender)) {
            return amount;
        }
        return amount * _balanceCoeff;
    }

    /**
     * @dev Checks if `recipient` won't have more than max balance after a transfer.
     */
    function _checkMaxBalance(address recipient, uint256 incoming)
        private
        view
        returns (bool)
    {
        if (isLimitless(recipient)) {
            return true;
        }
        uint256 newBalance = _balances[recipient] + incoming;
        return (newBalance / _balanceCoeff) <= getMaxBalance();
    }

    /**
     * @dev Returns the current maximum balance.
     */
    function getMaxBalance() public view returns (uint256) {
        return _minMaxBalance + _circulation / 100;
    }

    /**
     * @dev Returns the current balance coefficient.
     */
    function getCurrentCoeff() public view returns (uint256) {
        return _balanceCoeff;
    }

    /**
     * @dev Remove `amount` from msg.sender and reflect it on all holders.
     *
     * Requirements:
     *
     * - `amount` shouldn't be bigger than the msg.sender balance.
     */
    function deliver(uint256 amount) external {
        address sender = _msgSender();
        uint256 outgoing = _getTransferAmount(sender, amount);

        require(
            outgoing <= _balances[sender],
            "Kenshi: Cannot deliver more than the owned balance"
        );

        _balances[sender] = _balances[sender] - outgoing;

        if (isExcluded(sender)) {
            _totalExcluded = _totalExcluded - amount;
            _circulation = _totalSupply - _totalExcluded;
        }

        _balanceCoeff = _balanceCoeff - (_balanceCoeff * amount) / _circulation;

        require(
            _balanceCoeff > _minBalanceCoeff,
            "Kenshi: Coefficient smaller than the minimum defined"
        );

        emit Reflect(amount);
    }

    event InvestmentPercentageChanged(uint8 percentage);

    /**
     * @dev Sets the treasury `percentage`, indirectly sets rewards percentage.
     *
     * Requirements:
     *
     * - percentage should be equal to or smaller than 100
     *
     * emits a {InvestmentPercentageChanged} event.
     */
    function setInvestPercentage(uint8 percentage) external onlyOwner {
        require(percentage <= 100);
        _investPercentage = percentage;
        emit InvestmentPercentageChanged(percentage);
    }

    /**
     * @dev Returns the investment percentage.
     */
    function getInvestPercentage() external view returns (uint8) {
        return _investPercentage;
    }

    event BaseTaxChanged(uint8 percentage);

    /**
     * @dev Sets the base tax `percentage`.
     *
     * Requirements:
     *
     * - percentage should be equal to or smaller than 15
     *
     * emits a {BaseTaxChanged} event.
     */
    function setBaseTaxPercentage(uint8 percentage) external onlyOwner {
        require(percentage <= 15);
        _baseTax = percentage;
        emit BaseTaxChanged(percentage);
    }

    /**
     * @dev Returns the base tax percentage.
     */
    function getBaseTaxPercentage() external view returns (uint8) {
        return _baseTax;
    }

    /**
     * @dev Sets the trading to open, allows making transfers.
     */
    function openTrades() external onlyOwner {
        _tradeOpen = true;
    }

    /**
     * @dev Sets `treasury` addr for collecting investment tokens.
     *
     * Requirements:
     *
     * - `treasury` should not be address(0)
     */
    function setTreasuryAddr(address treasury) external onlyOwner {
        require(treasury != address(0), "Kenshi: Cannot set treasury to 0x0");
        _treasuryAddr = treasury;

        _excludedFromTax[_treasuryAddr] = true;
        _excludedFromFines[_treasuryAddr] = true;
        _excludedFromReflects[_treasuryAddr] = true;
        _excludedFromMaxBalance[_treasuryAddr] = true;
    }

    event BurnThresholdChanged(uint256 threshold);

    /**
     * @dev Sets the `threshold` for automatic burns.
     *
     * emits a {BurnThresholdChanged} event.
     */
    function setBurnThreshold(uint256 threshold) external onlyOwner {
        _burnThreshold = threshold;
        emit BurnThresholdChanged(threshold);
    }

    /**
     * @dev Returns the burn threshold amount.
     */
    function getBurnThreshold() external view returns (uint256) {
        return _burnThreshold;
    }

    /**
     * @dev Sends `amount` of BEP20 `token` from contract address to `recipient`
     *
     * Useful if someone sent bep20 tokens to the contract address by mistake.
     */
    function recoverBEP20(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner returns (bool) {
        require(
            token != address(this),
            "Kenshi: Cannot recover Kenshi from the contract"
        );
        return IBEP20(token).transfer(recipient, amount);
    }
}
