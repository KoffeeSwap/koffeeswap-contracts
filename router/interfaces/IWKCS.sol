pragma solidity >=0.5.0;

interface IWKCS {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
