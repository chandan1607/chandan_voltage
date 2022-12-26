// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
contract AccessControl {
    using SafeMath for uint256;

    /* Events*/
    event Deposit(address indexed sender, uint256 value);
    event Submission(uint256 indexed transactionId);
    event Confirmation(address indexed sender, uint256 indexed transactionId);
    event Execution(uint256 indexed transactionId);
    event ExecutionFailure(uint256 indexed transactionId);
    event Revocation(address indexed sender, uint256 indexed transactionId);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event QuorumUpdate(uint256 quorum);
    event AdminTransfer(address indexed newAdmin);

    /* Storage*/
    address public admin;

    //  addresses track of owners
    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 quorum;

    //Modifiers 
     
    modifier onlyAdmin() {
        require(msg.sender == admin, "Admin restricted function");
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0), "Specified destination doesn't exist");
        _;
    }

    modifier ownerExistsMod(address owner) {
        require(isOwner[owner] == true, "This owner doesn't exist");
        _;
    }

    modifier notOwnerExistsMod(address owner) {
        require(isOwner[owner] == false, "This owner already exists");
        _;
    }

    
    //   Contract constructor setting msg.sender to admin
     
    constructor(address[] memory _owners) {
        admin = msg.sender;
        require(
            _owners.length >= 3,
            "There need to be atleast 3 initial signatories for this wallet"
        );
        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        uint256 num = SafeMath.mul(owners.length, 60);
        quorum = SafeMath.div(num, 100);
    }



    /**
     *  admin to add new owner to the wallet
     * owner Address of the new owner
     */
    function addOwner(address owner)
        public
        onlyAdmin
        notNull(owner)
        notOwnerExistsMod(owner)
    {
        // add owner
        isOwner[owner] = true;
        owners.push(owner);

        // emit event
        emit OwnerAddition(owner);

        // update quorum
        updateQuorum(owners);
    }

    /**
     * Allows admin to remove owner from the wallet
     */
    function removeOwner(address owner)
        public
        onlyAdmin
        notNull(owner)
        ownerExistsMod(owner)
    {
        // remove owner
        isOwner[owner] = false;

        // iterate over owners and remove the current owner
        for (uint256 i = 0; i < owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.pop();

        // update quorum
        updateQuorum(owners);
    }

    /**
     * Allows admin to transfer owner from one wallet to  another
     */
    function transferOwner(address _from, address _to)
        public
        onlyAdmin
        notNull(_from)
        notNull(_to)
        ownerExistsMod(_from)
        notOwnerExistsMod(_to)
    {
       
        for (uint256 i = 0; i < owners.length; i++)
            // if the curernt owner
            if (owners[i] == _from) {
                // replace with new owner address
                owners[i] = _to;
                break;
            }

        // reset owner addresses
        isOwner[_from] = false;
        isOwner[_to] = true;

        // emit events
        emit OwnerRemoval(_from);
        emit OwnerAddition(_to);
    }

    /**
         admin to transfer admin rights to another address
        newAdmin Address of the new admin
     */
    function renounceAdmin(address newAdmin) public onlyAdmin {
        admin = newAdmin;

        emit AdminTransfer(newAdmin);
    }

   
    function updateQuorum(address[] memory _owners) internal {
        uint256 num = SafeMath.mul(_owners.length, 60);
        quorum = SafeMath.div(num, 100);

        emit QuorumUpdate(quorum);
    }
}
interface IWallet {
    //Allows admin to add new owner to the wallet
    function addOwner(address owner) external;

    //Allows admin to remove owner from the wallet
    function removeOwner(address owner) external;

    //Allows admin to transfer owner from one wallet to  another
    function transferOwner(address _from, address _to) external;

    //Allows an owner to confirm a transaction.
    function confirmTransaction(uint256 transactionId) external;

    //Allows anyone to execute a confirmed transaction.
    function executeTransaction(uint256 transactionId) external;

    //Allows an owner to revoke a confirmation for a transaction.
    function revokeTransaction(uint256 transactionId) external;
}
contract AccessControlWallet is AccessControl {
    using SafeMath for uint256;

    IWallet _walletInterface;

    /**
     * Contract constructor instantiates wallet interface and sets msg.sender to admin
     */
    constructor(IWallet wallet_, address[] memory _owners) AccessControl(_owners){
        _walletInterface = IWallet(wallet_);
        admin = msg.sender;
    }

    /*
     * Blockchain get functions
     */

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getAdmin() external view returns (address) {
        return admin;
    }
}
contract MultiSigWallet is AccessControl {
    using SafeMath for uint256;
    /*
     * Storage
     */
    struct Transaction {
        bool executed;
        address destination;
        uint256 value;
        bytes data;
    }

    // transaction ID and keep a mapping of the same
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;
    Transaction[] public _validTransactions;

   
    mapping(uint256 => mapping(address => bool)) public confirmations;

    
    fallback() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    /*
     * Modifiers
     */
    modifier isOwnerMod(address owner) {
        require(
            isOwner[owner] == true,
            "You are not authorized for this action."
        );
        _;
    }

    modifier isConfirmedMod(uint256 transactionId, address owner) {
        require(
            confirmations[transactionId][owner] == false,
            "You have already confirmed this transaction."
        );
        _;
    }

    modifier isExecutedMod(uint256 transactionId) {
        require(
            transactions[transactionId].executed == false,
            "This transaction has already been executed."
        );
        _;
    }

    /**
     * Contract constructor sets initial owners
     */
    constructor(address[] memory _owners) AccessControl(_owners) {}

   
    function submitTransaction(
        address destination,
        uint256 value,
        bytes memory data
    ) public isOwnerMod(msg.sender) returns (uint256 transactionId) {
        
        transactionId = transactionCount;

     
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });

        // update new count
        transactionCount += 1;

        // emit event
        emit Submission(transactionId);

       
        confirmTransaction(transactionId);
    }

    /**
     *  to confirm a transaction.
     */
    function confirmTransaction(uint256 transactionId)
        public
        isOwnerMod(msg.sender)
        isConfirmedMod(transactionId, msg.sender)
        notNull(transactions[transactionId].destination)
    {
        
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);

       
        executeTransaction(transactionId);
    }

    /**
     * Allows anyone to execute a confirmed transaction.
     */
    function executeTransaction(uint256 transactionId)
        public
        isOwnerMod(msg.sender)
        isExecutedMod(transactionId)
    {
        uint256 count = 0;
        bool quorumReached;

        
        for (uint256 i = 0; i < owners.length; i++) {
       
            if (confirmations[transactionId][owners[i]]) count += 1;
            
            if (count >= quorum) quorumReached = true;
        }

        if (quorumReached) {
         
            Transaction storage txn = transactions[transactionId];
          
            txn.executed = true;

           
            (bool success, ) = txn.destination.call{value: txn.value}(txn.data);

            if (success) {
                _validTransactions.push(txn);
                emit Execution(transactionId);
            } else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

    /**
     * Allows an owner to revoke a confirmation for a transaction.
     */
    function revokeTransaction(uint256 transactionId)
        external
        isOwnerMod(msg.sender)
        isConfirmedMod(transactionId, msg.sender)
        isExecutedMod(transactionId)
        notNull(transactions[transactionId].destination)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    /**
     * get functions
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getValidTransactions()
        external
        view
        returns (Transaction[] memory)
    {
        return _validTransactions;
    }

    function getQuorum() external view returns (uint256) {
        return quorum;
    }
}
