// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {UniversalNFTStaking} from "../src/nftstaking.sol";
import "forge-std/console.sol";

contract UniversalNFTStakingTests is Test {
    UniversalNFTStaking uStaking;

    function setUp() public {
        uStaking = new UniversalNFTStaking(
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD, //initialOwner
            0x07e11D1A1543B0D0b91684eb741d1ab7D51ae237, //socket
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2, //inboundSwitchboard
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2 //outboundSwitchboard
        );
    }

    function test_stakeNFT() public pure {
        // uStaking.RaffleData raffle = new uStaking.RaffleData({
        //   1115111,

        // });

        // ustaking.stakeNft(raffle, 1115111);
        console.log("hello test");
    }
}
