// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./MultisigWallet.sol";

contract UsersFactory {
    MultisigWallet[] multisigWallets;
    mapping(MultisigWallet => address[]) ownersOfWallet;
    mapping(MultisigWallet => mapping(address => bool)) checkOwner;

    modifier onlyOwner(MultisigWallet _multisigWallet) {
        require(
            checkOwner[_multisigWallet][msg.sender],
            "Only Valid Owner can perform it."
        );
        _;
    }

    function createMultisigWallet(address[] memory _owners) public {
        MultisigWallet multisigWallet = new MultisigWallet(_owners);
        multisigWallets.push(multisigWallet);
        ownersOfWallet[multisigWallet] = _owners;
        for (uint256 i = 0; i < _owners.length; i++) {
            checkOwner[multisigWallet][_owners[i]] = true;
        }
    }

    function createTransaction(
        MultisigWallet _multisigWallet,
        address _to,
        uint256 _amount
    ) public onlyOwner(_multisigWallet) returns (bytes4) {
        return _multisigWallet.createTransaction(_to, _amount, msg.sender);
    }

    function approveTranscationByOwner(
        MultisigWallet _multisigWallet,
        bytes4 _transactionId
    ) public onlyOwner(_multisigWallet) {
        _multisigWallet.approveTranscation(_transactionId, msg.sender);
    }

    // Getter
    function getOwnersOfMultisigWallets(
        MultisigWallet _multisigWallet
    ) public view returns (address[] memory) {
        return ownersOfWallet[_multisigWallet];
    }

    function getMultisigWallets()
        public
        view
        returns (MultisigWallet[] memory)
    {
        return multisigWallets;
    }

    function getTransaction(
        MultisigWallet _multisigWallet,
        bytes4 _transactionId
    )
        public
        view
        onlyOwner(_multisigWallet)
        returns (
            bytes4 transactionId,
            address from,
            address to,
            uint256 amount,
            bool isExecuted,
            uint256 transactionTime
        )
    {
        return _multisigWallet.getTransaction(_transactionId);
    }

    function getTransactionHistory(
        MultisigWallet _multisigWallet
    ) public view onlyOwner(_multisigWallet) returns (bytes4[] memory) {
        return _multisigWallet.getTransactionHistory(msg.sender);
    }

    function getNumberOfApprovalRequired(
        MultisigWallet _multisigWallet
    ) public view returns (uint256) {
        return _multisigWallet.getNumberOfApprovalRequired();
    }

    function getTotalApprovalsOfTransaction(
        MultisigWallet _multisigWallet,
        bytes4 _transactionId
    ) public view returns (uint256) {
        return _multisigWallet.getTotalApprovalsOfTransaction(_transactionId);
    }

    function getWalletBalance(
        MultisigWallet _multisigWallet
    ) public view returns (uint256) {
        return _multisigWallet.getWalletBalance(address(_multisigWallet));
    }
}
