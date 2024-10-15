// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {RebelSweep} from "./rebelsweep.sol";

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

contract NFTRaffleAuction is Ownable {
    using SafeERC20 for IERC20;
    enum AuctionStatus {
        ACTIVE,
        INACTIVE,
        CONCLUDED,
        CANCLED
    }

    struct AuctionData {
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

    RebelSweep public rebelSweepErc20tokenAddress;

    uint256 public auctionCount;
    address public socket; // Socket Address on Sepolia
    address public inboundSwitchboard; // FAST Switchboard on Sepolia
    address public outboundSwitchboard; // FAST Switchboard on Sepolia

    mapping(uint256 => AuctionData) public auctionsData; // auctionId => auction data - auction data for the auction
    mapping(uint256 => mapping(uint256 => address)) public auctionTickits; // auctionId => (tickitId => userAddress) - list of auctions tickits and their owner.
    mapping(uint256 => mapping(address => uint256))
        public userAuctionTickitCount; // auctionId => (userAddress => no. tickit) - count of auctions tickits of users.
    mapping(uint256 => address[]) public auctionParticipants;
    mapping(uint256 => address) public auctionWinner;
    mapping(uint256 => uint256) public auctionTickitCount; // tickit counter for all auction

    /// @notice Event emitted when tickets are purchased.
    event MessageRecived(uint256 remoteChainSlug, AuctionData _auctionData);
    event TicketPurchased(
        uint256 indexed auctionId,
        address indexed buyer,
        uint256 count
    );
    event TicketRefund(
        uint256 indexed auctionId,
        address indexed buyer,
        uint256 count
    ); // !!
    event AuctionConcluded(
        uint256 indexed auctionId,
        AuctionData indexed auctionData,
        address indexed winner
    );
    event CancleAuction(
        uint256 indexed auctionId,
        AuctionData indexed auctionData
    );
    event AssetReleased(
        uint256 remoteChainSlug,
        AuctionData _auctionData,
        address _to
    );

    error InsufficientFees();

    constructor(
        address _rebelsweepToken,
        address initialOwner,
        address _socket,
        address _inboundSwitchboard,
        address _outboundSwitchboard
    ) Ownable(initialOwner) {
        rebelSweepErc20tokenAddress = RebelSweep(_rebelsweepToken); // rebelsweep erc20 token contract address
        socket = _socket;
        inboundSwitchboard = _inboundSwitchboard;
        outboundSwitchboard = _outboundSwitchboard;
    }

    modifier isOwner() {
        require(msg.sender == owner(), "Not owner");
        _;
    }

    modifier isSocket() {
        require(msg.sender == socket, "Not Socket");
        _;
    }

    /**
     * @notice Creates a new auction.
     * @param _auctionData The address of the NFT contract.
     */
    function createAuction(AuctionData memory _auctionData) public {
        auctionsData[auctionCount] = _auctionData;
        auctionCount++;
    }

    function updateAuction(
        uint _auctionId,
        AuctionData memory _auctionData
    ) public {
        auctionsData[_auctionId] = _auctionData;
    }

    /**
     * @notice Allows a user to buy raffle tickets for an auction.
     * @param _auctionId The ID of the auction.
     * @param _count The number of tickets to purchase.
     */
    function buyTickets(uint256 _auctionId, uint256 _count) external {
        // Retrieve auction data from storage once
        AuctionData storage auction = auctionsData[_auctionId];

        // Ensure the auction is active
        require(
            auction.auctionStatus == AuctionStatus.ACTIVE,
            "Auction is not active"
        );

        // Ensure the user is purchasing at least one ticket
        require(_count > 0, "Must purchase at least one ticket");

        // Calculate the total cost of the tickets
        uint256 totalCost = auction.tickitPrice * _count;
        require(totalCost != 0, "Total cost cannot be zero");

        // Transfer paymentToken (e.g., USDC) from the buyer to the contract
        auction.paymentToken.safeTransferFrom(
            msg.sender,
            address(this),
            totalCost
        );

        // Add the buyer to the auction participants if they haven't bought any tickets before
        if (userAuctionTickitCount[_auctionId][msg.sender] == 0) {
            auctionParticipants[_auctionId].push(msg.sender);
        }

        // Update the buyer's ticket count
        userAuctionTickitCount[_auctionId][msg.sender] += _count;

        // Assign tickets to the buyer in the auctionTickits mapping
        for (uint256 i = 0; i < _count; i++) {
            auctionTickits[_auctionId][auctionTickitCount[_auctionId]] = msg
                .sender;
            auctionTickitCount[_auctionId]++;
        }

        // Emit the event for ticket purchase
        emit TicketPurchased(_auctionId, msg.sender, _count);
    }

    /**
     * @notice Checks if the ticket threshold has been reached and the minimum time has passed.
     * @param _auctionId The ID of the auction.
     * @return thresholdReached A boolean indicating if the threshold is met.
     * @return minTimeReached A boolean indicating if the minimum time has passed.
     */
    function checkThresold(
        uint256 _auctionId
    ) public view returns (bool thresholdReached, bool minTimeReached) {
        // Check if the number of tickets sold meets or exceeds the ticket threshold
        thresholdReached =
            auctionTickitCount[_auctionId] >=
            auctionsData[_auctionId].tickitThreshold;

        // Check if the current block timestamp is greater than or equal to the minimum time required
        minTimeReached =
            block.timestamp >= auctionsData[_auctionId].timeThreshold;

        // Return the results
        return (thresholdReached, minTimeReached);
    }

    function selectRandomTickitOwner(
        uint256 _auctionId
    ) internal view returns (address) {
        uint256 tickitCount = auctionTickitCount[_auctionId];
        uint256 randomIndex = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    msg.sender,
                    block.prevrandao,
                    tickitCount
                )
            )
        ) % tickitCount; // need to add chainlink here
        return auctionTickits[_auctionId][randomIndex];
    }

    /**
     * @notice Cancels an ongoing auction and refunds all participants.
     * @dev Refunds the payment tokens to each participant based on the number of tickets they purchased.
     * @param _auctionId The ID of the auction to cancel.
     */
    function cancelAuction(uint256 _auctionId, uint32 _dstEid) public payable {
        AuctionData memory auction = auctionsData[_auctionId];

        // Ensure that only the auction owner can cancel the auction
        require(
            msg.sender == auction.owner,
            "Only the auction owner can cancel the auction"
        );

        // Check if the auction has not been concluded yet
        require(
            auction.auctionStatus != AuctionStatus.CONCLUDED,
            "Auction is already concluded"
        );

        // Iterate over all participants and refund their payment
        address[] memory participants = auctionParticipants[_auctionId];
        for (uint256 i = 0; i < participants.length; i++) {
            address participant = participants[i];
            uint256 refundAmount = userAuctionTickitCount[_auctionId][
                participant
            ] * auction.tickitPrice;

            // Transfer the refund amount back to the participant
            auction.paymentToken.safeTransfer(participant, refundAmount);
            // Emit the event for ticket refund to the participant
            emit TicketRefund(
                _auctionId,
                participant,
                userAuctionTickitCount[_auctionId][participant]
            );
        }

        auction.auctionStatus = AuctionStatus.CANCLED;
        auctionsData[_auctionId] = auction;
        sendMessage(auction, 50000, _dstEid);

        // CancleAuction Event
        emit CancleAuction(_auctionId, auction);
    }

    /**
     * @notice Concludes an auction by selecting a winner and distributing the NFT.
     * @dev The winner is selected using Chainlink VRF for randomness. The NFT is transferred to the winner,
     *      and the remaining funds (minus the winner's tickets) are minted as additional rewards for other participants.
     * @param _auctionId The ID of the auction to conclude.
     */
    function concludeAuction(uint256 _auctionId) public {
        // Ensure that the auction can be concluded
        (bool thresholdReached, bool minTimeReached) = checkThresold(
            _auctionId
        );
        require(
            thresholdReached && minTimeReached,
            "Threshold not met or minimum time not reached"
        );

        // Select the winner using Chainlink VRF
        address winner = selectRandomTickitOwner(_auctionId);
        // auctionWinner[_auctionId] = winner;
        auctionsData[_auctionId].winner = winner;

        // Calculate total tickets sold and winner's tickets
        uint256 totalTickets = auctionTickitCount[_auctionId];
        uint256 winnerTickets = userAuctionTickitCount[_auctionId][winner];

        // Transfer the NFT to the winner

        // Distribute additional rewards (if any) to other participants
        uint256 rewardPool = totalTickets - winnerTickets;
        if (rewardPool > 0) {
            address[] memory participants = auctionParticipants[_auctionId];
            for (uint256 i = 0; i < participants.length; i++) {
                address participant = participants[i];
                if (participant != winner) {
                    uint256 participantTickets = userAuctionTickitCount[
                        _auctionId
                    ][participant];
                    rebelSweepErc20tokenAddress.mint(
                        participant,
                        participantTickets * 10 * 10 ** 18
                    );
                }
            }
        }

        auctionsData[_auctionId].auctionStatus = AuctionStatus.CONCLUDED;

        sendMessage(
            auctionsData[_auctionId],
            50000,
            auctionsData[_auctionId].chainId
        );

        // Emit an event for auction conclusion
        emit AuctionConcluded(_auctionId, auctionsData[_auctionId], winner);
    }

    /************************************************************************
        Config Functions 
    ************************************************************************/

    /**
     * @dev Configures plug to send/receive message
     */
    function connectPlug(
        uint32 remoteChainSlug,
        address siblingPlug_
    ) external isOwner {
        ISocket(socket).connect(
            remoteChainSlug,
            siblingPlug_,
            inboundSwitchboard,
            outboundSwitchboard
        );
    }

    /**
     * @dev Sets destination chain gas limit
     */
    // function setDestGasLimit(uint256 _destGasLimit) external isOwner {
    //     destGasLimit = _destGasLimit;
    // }

    // function setRemoteChainSlug(uint32 _remoteChainSlug) external isOwner {
    //     remoteChainSlug = _remoteChainSlug;
    // }

    function setSocketAddress(address _socket) external isOwner {
        socket = _socket;
    }

    function setSwitchboards(
        address _inboundSwitchboard,
        address _outboundSwitchboard
    ) external isOwner {
        inboundSwitchboard = _inboundSwitchboard;
        outboundSwitchboard = _outboundSwitchboard;
    }

    /************************************************************************
        Send Messages
    ************************************************************************/

    /**
     * @dev Sends message to remote chain plug
     */
    function sendMessage(
        AuctionData memory _auctionData,
        uint256 destGasLimit,
        uint256 remoteChainSlug
    ) internal {
        bytes memory payload = abi.encode(_auctionData);

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

        emit AssetReleased(remoteChainSlug, _auctionData, _auctionData.winner);
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
    function _receiveMessage(
        uint256 _srcChainSlug,
        AuctionData memory _message
    ) internal {
        createAuction(_message);
        emit MessageRecived(_srcChainSlug, _message);
    }

    /**
     * @dev Called by Socket when sending destination payload
     */
    function inbound(
        uint256 srcChainSlug_,
        bytes calldata payload_
    ) external isSocket {
        AuctionData memory _message = abi.decode(payload_, (AuctionData));
        _receiveMessage(srcChainSlug_, _message);
    }
}
