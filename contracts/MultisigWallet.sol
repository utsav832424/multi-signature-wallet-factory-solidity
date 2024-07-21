// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MultisigWallet {
    error MultisigWallet__TransferFailed();
    error MultisigWallet__ApprovalExpired();
    error MultisigWallet__NotEnoughApprovals();

    event TransactionCreated(
        bytes4 transactionId,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event TransactionApproved(bytes4 transactionId, address indexed approver);
    event TransactionExecuted(
        bytes4 transactionId,
        address indexed to,
        uint256 amount
    );
    event TransactionExpired(bytes4 transactionId);

    struct Transaction {
        bytes4 transactionId;
        address from;
        address to;
        uint256 amount;
        bool isExecuted;
        uint256 transactionTime;
    }

    address[] owners;

    uint256 numberOfApprovalRequired;
    uint256 constant AMOUNT_TO_WEI = 10**18;
    uint256 constant APPROVAL_VALIDITY = 60;
    uint256 constant TIMELOCK_PERIOD = 60;

    mapping(bytes4 => Transaction) ownerTransaction;
    mapping(address => bytes4[]) transactionsHistory;
    mapping(address => mapping(bytes4 => bool)) approvelsOfOwners;
    mapping(bytes4 => uint256) approverCount;
    mapping(bytes4 => bool) transactionExist;
    mapping(address => uint256) lockedAmount;

    modifier isNotApproved(bytes4 _transactionId, address approver) {
        require(
            !approvelsOfOwners[approver][_transactionId],
            "Already Approved."
        );
        _;
    }

    modifier isTransactionExist(bytes4 _transactionId) {
        require(transactionExist[_transactionId], "Transaction dosen't exist.");
        _;
    }

    modifier isTransactionExecuted(bytes4 _transactionId) {
        require(
            !ownerTransaction[_transactionId].isExecuted,
            "Transaction already Executed."
        );
        _;
    }

    /**
     * @dev Constructor to initialize the MultisigWallet with owners
     * @param _owners Array of initial owners
     */
    constructor(address[] memory _owners) {
        require(_owners.length > 0, "Owner should not be 0.");
        owners = _owners;
        numberOfApprovalRequired = (_owners.length / 2) + 1;
    }

    /**
     * @dev Create a new transaction
     * @param _to The address to send the transaction to
     * @param _amount The amount to send in the transaction
     * @param _owner The address of the transaction creator
     * @return bytes4 The ID of the created transaction
     */
    function createTransaction(
        address _to,
        uint256 _amount,
        address _owner
    ) public returns (bytes4) {
        uint256 payableAmount = _amount * AMOUNT_TO_WEI;
        require(
            payableAmount <=
                address(this).balance - lockedAmount[address(this)],
            "Insufficiant Balance in wallet."
        );

        bytes4 _transactionId = bytes4(
            keccak256(abi.encodePacked(_to, payableAmount, block.timestamp))
        );

        Transaction memory _transaction = Transaction({
            transactionId: _transactionId,
            from: _owner,
            to: _to,
            amount: payableAmount,
            isExecuted: false,
            transactionTime: block.timestamp
        });

        lockedAmount[address(this)] += payableAmount;
        ownerTransaction[_transactionId] = _transaction;
        transactionsHistory[_owner].push(_transactionId);

        transactionExist[_transactionId] = true;
        approvelsOfOwners[_owner][_transactionId] = true;
        approverCount[_transactionId]++;

        emit TransactionCreated(_transactionId, msg.sender, _to, payableAmount);
        return _transactionId;
    }

    /**
     * @dev Approve a transaction
     * @param _transactionId The ID of the transaction to approve
     * @param approver The address of the approver
     */
    function approveTranscation(bytes4 _transactionId, address approver)
        public
        isTransactionExist(_transactionId)
        isTransactionExecuted(_transactionId)
        isNotApproved(_transactionId, approver)
    {
        Transaction storage transaction = ownerTransaction[_transactionId];
        if (
            block.timestamp > transaction.transactionTime + APPROVAL_VALIDITY &&
            !transaction.isExecuted
        ) {
            _expireTransaction(_transactionId);
            revert MultisigWallet__ApprovalExpired();
        }

        approvelsOfOwners[approver][_transactionId] = true;
        approverCount[_transactionId]++;
        emit TransactionApproved(_transactionId, msg.sender);

        if (approverCount[_transactionId] >= numberOfApprovalRequired) {
            executeTransaction(_transactionId);
        }
    }

    /**
     * @dev Internal function to expire a transaction
     * @param _transactionId The ID of the transaction to expire
     */
    function _expireTransaction(bytes4 _transactionId) internal {
        Transaction storage transaction = ownerTransaction[_transactionId];
        lockedAmount[address(this)] -= transaction.amount;
        transactionExist[_transactionId] = false;
        emit TransactionExpired(_transactionId);
    }

    /**
     * @dev Internal function to execute a transaction
     * @param _transactionId The ID of the transaction to execute
     */
    function executeTransaction(bytes4 _transactionId)
        internal
        isTransactionExist(_transactionId)
        isTransactionExecuted(_transactionId)
    {
        Transaction storage transaction = ownerTransaction[_transactionId];
        require(
            block.timestamp >= transaction.transactionTime + TIMELOCK_PERIOD,
            "Timelock period not met"
        );
        if (approverCount[_transactionId] < numberOfApprovalRequired) {
            revert MultisigWallet__NotEnoughApprovals();
        }

        lockedAmount[address(this)] -= transaction.amount;
        transaction.isExecuted = true;
        (bool success, ) = payable(transaction.to).call{
            value: transaction.amount
        }("");
        if (!success) {
            revert MultisigWallet__TransferFailed();
        }

        emit TransactionExecuted(
            _transactionId,
            transaction.to,
            transaction.amount
        );
    }

    // Getter Functions
    /**
     * @dev Get the details of a transaction
     * @param _transactionId The ID of the transaction to retrieve
     * @return transactionId The ID of the transaction
     * @return from The address from which the transaction was created
     * @return to The address to which the transaction is sent
     * @return amount The amount of the transaction
     * @return isExecuted The execution status of the transaction
     * @return transactionTime The timestamp of the transaction creation
     */
    function getTransaction(bytes4 _transactionId)
        public
        view
        returns (
            bytes4 transactionId,
            address from,
            address to,
            uint256 amount,
            bool isExecuted,
            uint256 transactionTime
        )
    {
        Transaction memory transactionOfUser = ownerTransaction[_transactionId];
        return (
            transactionOfUser.transactionId,
            transactionOfUser.from,
            transactionOfUser.to,
            transactionOfUser.amount,
            transactionOfUser.isExecuted,
            transactionOfUser.transactionTime
        );
    }

    /**
     * @dev Get the transaction history of an owner
     * @param owner The address of the owner
     * @return bytes4[] Array of transaction IDs associated with the owner
     */
    function getTransactionHistory(address owner)
        public
        view
        returns (bytes4[] memory)
    {
        return transactionsHistory[owner];
    }

    /**
     * @dev Get the number of approvals required for a transaction
     * @return uint256 The number of approvals required
     */
    function getNumberOfApprovalRequired() public view returns (uint256) {
        return numberOfApprovalRequired;
    }

    /**
     * @dev Get the total number of approvals for a transaction
     * @param _transactionId The ID of the transaction
     * @return uint256 The total number of approvals
     */
    function getTotalApprovalsOfTransaction(bytes4 _transactionId)
        public
        view
        returns (uint256)
    {
        return approverCount[_transactionId];
    }

    /**
     * @dev Get the balance of a wallet
     * @param _walletAddress The address of the wallet
     * @return uint256 The balance of the wallet
     */
    function getWalletBalance(address _walletAddress)
        public
        view
        returns (uint256)
    {
        return _walletAddress.balance - lockedAmount[_walletAddress];
    }

    receive() external payable {}
}
