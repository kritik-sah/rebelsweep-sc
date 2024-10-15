// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface ISocket {
    function outbound(
        uint256 remoteChainSlug_,
        uint256 minMsgGasLimit_,
        bytes32 executionParams_,
        bytes32 transmissionParams_,
        bytes calldata payload_
    ) external payable returns (bytes32 msgId);

    function connect(
        uint32 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external;

    function getMinFees(
        uint256 minMsgGasLimit_,
        uint256 payloadSize_,
        bytes32 executionParams_,
        bytes32 transmissionParams_,
        uint256 remoteChainSlug_,
        address plug_
    ) external view returns (uint256 totalFees);
}

contract UniversalNFTStaking is Ownable {
    using SafeERC20 for IERC20;
    enum AuctionStatus {
        ACTIVE,
        INACTIVE,
        CONCLUDED,
        CANCLED
    }

    struct RaffleData {
        uint256 chainId;
        address nftContract;
        uint256 tokenId;
        address owner;
        address winner;
        uint256 tickitPrice;
        uint256 tickitThreshold;
        uint256 timeThreshold;
        AuctionStatus auctionStatus;
        IERC20 paymentToken; // user defined payment token
    }

    address public socket; // Socket Address on Sepolia
    address public inboundSwitchboard; // FAST Switchboard on Sepolia
    address public outboundSwitchboard; // FAST Switchboard on Sepolia

    mapping(address => mapping(uint256 => RaffleData)) public raffles;
    mapping(address => uint256[]) public stakedTokens;

    event MessageSent(RaffleData raffle, uint32 dstEid);
    event NFTStaked(RaffleData indexed raffle, uint256 timestamp);
    event NFTUnstaked(RaffleData indexed raffle, uint256 timestamp);

    error InsufficientFees();

    constructor(
        address initialOwner,
        address _socket,
        address _inboundSwitchboard,
        address _outboundSwitchboard
    ) Ownable(initialOwner) {
        socket = _socket;
        inboundSwitchboard = _inboundSwitchboard;
        outboundSwitchboard = _outboundSwitchboard;
    }

    modifier isSocket() {
        require(msg.sender == socket, "Not Socket");
        _;
    }

    // address nftContract, uint256 tokenId, uint256 tickitPrice, uint256 tickitThreshold, uint256 minTime)
    function stakeNFT(
        RaffleData calldata raffle,
        uint256 remoteChainSlug
    ) external payable {
        IERC721 nftToken = IERC721(raffle.nftContract);
        require(
            nftToken.ownerOf(raffle.tokenId) == msg.sender,
            "You do not own this NFT"
        );

        // Transfer the NFT from the sender to this contract
        nftToken.safeTransferFrom(msg.sender, address(this), raffle.tokenId);

        // Record the raffle
        raffles[raffle.nftContract][raffle.tokenId] = RaffleData({
            chainId: block.chainid,
            nftContract: raffle.nftContract,
            tokenId: raffle.tokenId,
            owner: msg.sender,
            winner: address(0),
            tickitPrice: raffle.tickitPrice,
            tickitThreshold: raffle.tickitThreshold,
            timeThreshold: raffle.timeThreshold,
            auctionStatus: AuctionStatus.INACTIVE,
            paymentToken: IERC20(raffle.paymentToken)
        });
        stakedTokens[msg.sender].push(raffle.tokenId);
        sendMessage(
            raffles[raffle.nftContract][raffle.tokenId],
            5000,
            remoteChainSlug
        );
        // Emit the NFTStaked event
        emit NFTStaked(raffle, block.timestamp);
    }

    function unstakeNFT(RaffleData memory _raffle) internal {
        // Transfer the NFT back to the owner or winner
        if (_raffle.winner == address(0)) {
            IERC721(_raffle.nftContract).safeTransferFrom(
                address(this),
                _raffle.owner,
                _raffle.tokenId
            );
        } else {
            IERC721(_raffle.nftContract).safeTransferFrom(
                address(this),
                _raffle.winner,
                _raffle.tokenId
            );
        }
        // Emit the NFTUnstaked event
        emit NFTUnstaked(_raffle, block.timestamp);
    }

    /************************************************************************
        Send Messages
    ************************************************************************/

    /**
     * @dev Sends message to remote chain plug
     */
    function sendMessage(
        RaffleData memory _raffleData,
        uint256 destGasLimit,
        uint256 remoteChainSlug
    ) public payable {
        bytes memory payload = abi.encode(_raffleData);

        uint256 totalFees = _getMinimumFees(
            destGasLimit,
            payload.length,
            remoteChainSlug
        );

        if (msg.value < totalFees) revert InsufficientFees();

        ISocket(socket).outbound{value: msg.value}(
            remoteChainSlug,
            destGasLimit,
            bytes32(0),
            bytes32(0),
            payload
        );

        // emit AssetReleased(remoteChainSlug, _raffleData, _auctionData.winner);
    }

    function _getMinimumFees(
        uint256 minMsgGasLimit_,
        uint256 payloadSize_,
        uint256 remoteChainSlug
    ) internal view returns (uint256) {
        return
            ISocket(socket).getMinFees(
                minMsgGasLimit_,
                payloadSize_,
                bytes32(0),
                bytes32(0),
                remoteChainSlug,
                address(this)
            );
    }

    /************************************************************************
        Receive Messages
    ************************************************************************/

    /**
     * @dev Sets new message on destination chain and emits event
     */
    function _receiveMessage(RaffleData memory _message) internal {
        unstakeNFT(_message);
    }

    /**
     * @dev Called by Socket when sending destination payload
     */
    function inbound(
        // uint32 srcChainSlug_,
        bytes calldata payload_
    ) external isSocket {
        RaffleData memory _message = abi.decode(payload_, (RaffleData));
        _receiveMessage(_message);
    }
}
