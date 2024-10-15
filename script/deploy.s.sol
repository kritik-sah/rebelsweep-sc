// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/rebelsweep.sol";
import "../src/nftstaking.sol";
import {NFTRaffleAuction} from "../src/auctioncontract.sol";

contract deployContracts {
    function run() public {
        RebelSweep rSweep = new RebelSweep(
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD, //defaultAdmin
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD, //pauser
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD //minter
        );
        UniversalNFTStaking uStaking = new UniversalNFTStaking(
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD, //initialOwner
            0x07e11D1A1543B0D0b91684eb741d1ab7D51ae237, //socket
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2, //inboundSwitchboard
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2 //outboundSwitchboard
        );

        NFTRaffleAuction nftRaffle = new NFTRaffleAuction(
            address(rSweep), //_rebelsweepToken
            0x0CAD9Ce859D4c1D81204eAA01332cFDFa3d141eD, //initialOwner
            0x07e11D1A1543B0D0b91684eb741d1ab7D51ae237, //socket
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2, //inboundSwitchboard
            0x501fCBa3e6F92b2D1d89038FeD56EdacaaF5f7c2 //outboundSwitchboard;
        );
    }
}
