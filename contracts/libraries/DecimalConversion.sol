//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

library DecimalConversion {
    function from6to18dec(uint _num) pure public returns(uint) {
        return (_num * 10**12);
    }
    function from18to6dec(uint _num) pure public returns(uint) {
        return (_num / 10**12);
    }
}