// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract Bank {
    mapping(address => uint256) private balances;
    mapping(address => bool)    private authorizedAddresses;

    event RefundAvailable(address user, uint256 value);

    constructor() {
        authorizedAddresses[msg.sender] = true;
    }

    function addAuthorizedAddress(address newContract) external returns (bool) {
        require(authorizedAddresses[msg.sender]);

        authorizedAddresses[newContract] = true;

        return true;
    }

    function deleteAuthorizedAddress() external returns (bool) {
        require(authorizedAddresses[msg.sender]);
        
        authorizedAddresses[msg.sender] = false;

        return true;
    }

    function assignRefund(address user, uint256 value) external returns (bool) {
        require(authorizedAddresses[msg.sender]);
        balances[user] += value;

        emit RefundAvailable(user, value);

        return true;
    }

    function getBalance() public view returns (uint256) {
        return balances[msg.sender];
    }

    function withdraw() public {
        uint256 value        = balances[msg.sender];
        balances[msg.sender] = 0;

        payable(msg.sender).transfer(value);
    }

    receive() external payable {}
}