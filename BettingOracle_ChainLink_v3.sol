// SPDX-License-Identifier: BUSL-1.1
//BettingOracle_ChainLink v3.1
//bsc testnet
//bsc mainnet
//ethereum mainnet
//sepolia testnet

pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract BettingOracle_ChainLink_v3 {
    address public developer;

    AggregatorV3Interface internal priceFeed;

    struct ChainLink_Price_Feed_Contract_Addresses {
        uint256 id;
        string pair_name;
        address betting_token;
        uint256 betting_token_decimails;
        address ENS_address;
        AggregatorV3Interface this_priceFeed;
        uint ENS_address_decimails;
        bool valid;
    }

    mapping(uint256 => ChainLink_Price_Feed_Contract_Addresses)
        public pair_name_in_contract_addresses;

    uint256 public ContractAddresses_Id;
    uint256 public current_ContractAddresses_Id;

    uint public returned_target_price;
    int256 public target_price;
    uint80 public target_roundID;

    uint256 private constant PHASE_OFFSET = 64;

    //round_id deduction adjustment
    /**
     * bsc mainnet = 10000
     * ethereum mainnet = 2000
     */
    uint80 _deduction;

    //ini_timestamp_difference adjustment
    /**
     * bsc mainnet = 30
     * ethereum mainnet = 300
     */
    uint _ini_timestamp_difference;

    /**
     * Network: Sepolia
     * Aggregator: ETH/USD
     * Address:	0x694AA1769357215DE4FAC081bf1f309aDC325306
     */
    /**
     * Network: Sepolia
     * Aggregator: BTC/USD
     * Address: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
     */
    /**
     * Network: Sepolia
     * Aggregator: USDC / USD
     * Address: 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
     */
    constructor(uint80 deduction, uint ini_timestamp_difference) {
        developer = msg.sender;
        _deduction = deduction;
        _ini_timestamp_difference = ini_timestamp_difference;
    }

    /**
     * to fetch price feed data obj
     * parameters:
     * pair_name: pair name of returned price feed data struct
     */
    function fetch_betting_token_from_ChainLink_Price_Feed_Contract_Addresses_obj(
        string calldata pair_name
    ) public view returns (address, uint256, bool) {
        address betting_token;
        uint256 betting_token_decimails;
        bool valid;

        // get token decimals
        for (uint256 i = 0; i <= ContractAddresses_Id; i++) {
            if (
                keccak256(
                    bytes(pair_name_in_contract_addresses[i].pair_name)
                ) ==
                keccak256(bytes(pair_name)) &&
                pair_name_in_contract_addresses[i].valid == true
            ) {
                betting_token = pair_name_in_contract_addresses[i]
                    .betting_token;
                betting_token_decimails = pair_name_in_contract_addresses[i]
                    .betting_token_decimails;
                valid = pair_name_in_contract_addresses[i].valid;

                break;
            }
        }

        return (betting_token, betting_token_decimails, valid);
    }

    /**
     * to update ChainLink round id deduction to increase the success rates in looping process.
     * parameters:
     * deduction: values to deduct in roundid
     */
    function update_round_id_deduction(uint80 deduction) public {
        require(
            developer == msg.sender,
            "only developer can update round_id deduction!"
        );

        _deduction = deduction;
    }

    /**
     * to update initial timestamp difference to increase the success rates in looping process.
     * parameters:
     * ini_timestamp_difference: values to set the initial timestamp difference
     */
    function update_ini_timestamp_difference(
        uint ini_timestamp_difference
    ) public {
        require(
            developer == msg.sender,
            "only developer can update ini_timestamp_difference!"
        );

        _ini_timestamp_difference = ini_timestamp_difference;
    }

    /**
     * to add ChainLink ENS address into struct ChainLink_Price_Feed_Contract_Addresses.
     * parameters:
     * string pair name of ens address.
     * ENS_address: https://docs.chain.link/data-feeds/price-feeds/addresses
     */
    function add_ENS_address(
        string calldata pair_name,
        address betting_token,
        uint256 betting_token_decimails,
        address ENS_address
    ) public returns (uint256) {
        require(developer == msg.sender, "only developer can add ENS address!");

        ContractAddresses_Id++;

        AggregatorV3Interface this_priceFeed = AggregatorV3Interface(
            ENS_address
        );

        uint ENS_address_decimails = this_priceFeed.decimals();

        ChainLink_Price_Feed_Contract_Addresses
            storage new_ChainLink_Price_Feed_Contract_Addresses = pair_name_in_contract_addresses[
                ContractAddresses_Id
            ];
        new_ChainLink_Price_Feed_Contract_Addresses.id = ContractAddresses_Id;
        new_ChainLink_Price_Feed_Contract_Addresses.pair_name = pair_name;
        new_ChainLink_Price_Feed_Contract_Addresses
            .betting_token = betting_token;
        new_ChainLink_Price_Feed_Contract_Addresses
            .betting_token_decimails = betting_token_decimails;
        new_ChainLink_Price_Feed_Contract_Addresses.ENS_address = ENS_address;
        new_ChainLink_Price_Feed_Contract_Addresses
            .this_priceFeed = this_priceFeed;
        new_ChainLink_Price_Feed_Contract_Addresses
            .ENS_address_decimails = ENS_address_decimails;
        new_ChainLink_Price_Feed_Contract_Addresses.valid = true;

        return ContractAddresses_Id;
    }

    /**
     * to set ChainLink ENS address for current price feed query of indicated token address.
     * parameters:
     * token_address:supported ERC20 token address in struct ChainLink_Price_Feed_Contract_Addresses.
     * returns: AggregatorV3Interface object
     */
    function set_ENS_address(
        string calldata pair_name
    ) public returns (AggregatorV3Interface) {
        if (
            current_ContractAddresses_Id != 0 &&
            keccak256(
                bytes(
                    pair_name_in_contract_addresses[
                        current_ContractAddresses_Id
                    ].pair_name
                )
            ) ==
            keccak256(bytes(pair_name))
        ) {
            return
                pair_name_in_contract_addresses[current_ContractAddresses_Id]
                    .this_priceFeed;
        } else {
            bool priceFeed_exist = false;

            for (uint256 i = 0; i <= ContractAddresses_Id; i++) {
                if (
                    keccak256(
                        bytes(pair_name_in_contract_addresses[i].pair_name)
                    ) ==
                    keccak256(bytes(pair_name)) &&
                    pair_name_in_contract_addresses[i].valid == true
                ) {
                    priceFeed = pair_name_in_contract_addresses[i]
                        .this_priceFeed;
                    current_ContractAddresses_Id = i;
                    priceFeed_exist = true;
                }
            }

            require(
                priceFeed_exist == true,
                "token address is not supported @ set_ENS_address()!"
            );

            return priceFeed;
        }
    }

    /**
     * to update ChainLink ENS address in struct ChainLink_Price_Feed_Contract_Addresses.
     * parameters:
     * id: id of ChainLink_Price_Feed_Contract_Addresses
     * pair_name:pair name of ens address in the ChainLink_Price_Feed_Contract_Addresses.
     * ENS_address: https://docs.chain.link/data-feeds/price-feeds/addresses
     * valid: valid or not for this address in the ChainLink_Price_Feed_Contract_Addresses.
     */
    function update_ENS_address(
        uint256 id,
        string calldata pair_name,
        address betting_token,
        uint256 betting_token_decimails,
        address ENS_address,
        bool valid
    ) public {
        require(
            developer == msg.sender,
            "only developer can update ENS address!"
        );

        AggregatorV3Interface this_priceFeed = AggregatorV3Interface(
            ENS_address
        );

        uint ENS_address_decimails = this_priceFeed.decimals();

        pair_name_in_contract_addresses[id].pair_name = pair_name;
        pair_name_in_contract_addresses[id].betting_token = betting_token;
        pair_name_in_contract_addresses[id]
            .betting_token_decimails = betting_token_decimails;
        pair_name_in_contract_addresses[id].ENS_address = ENS_address;
        pair_name_in_contract_addresses[id].this_priceFeed = this_priceFeed;
        pair_name_in_contract_addresses[id]
            .ENS_address_decimails = ENS_address_decimails;
        pair_name_in_contract_addresses[id].valid = valid;
    }

    /**
     * Returns the round data.
     */
    function getRoundData(
        uint80 _roundId
    ) public view returns (uint80, int256, uint256, uint256, uint80) {
        // prettier-ignore
        (
            uint80 roundID,
            int256 answer,
            uint startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.getRoundData(_roundId);
        return (roundID, answer, startedAt, updatedAt, answeredInRound);
    }

    /**
     * Returns the latest price.
     */
    function getLatestPrice()
        public
        view
        returns (uint80, int, uint, uint, uint80)
    {
        // prettier-ignore
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        return (roundID, price, startedAt, timeStamp, answeredInRound);
    }

    /**
     * Returns historical price for a round id.
     * roundId is NOT incremental. Not all roundIds are valid.
     * You must know a valid roundId before consuming historical data.
     *
     * ROUNDID VALUES:
     *    InValid:      18446744073709562300
     *    Valid:        18446744073709554683
     *
     * @dev A timestamp with zero value means the round is not complete and should not be used.
     */
    function getHistoricalPrice(
        uint80 roundId
    ) public view returns (int256, uint) {
        // prettier-ignore
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            uint timeStamp,
            /*uint80 answeredInRound*/
        ) = priceFeed.getRoundData(roundId);
        //require(timeStamp > 0, "Round not complete");
        if (timeStamp == 0) {
            price = 0;
        }
        return (price, timeStamp);
    }

    /**
     * to calculate phaseId and aggregatorRoundId by roundId
     */
    function parseIds(uint256 _roundId) public pure returns (uint16, uint64) {
        uint16 phaseId = uint16(_roundId >> PHASE_OFFSET);
        uint64 aggregatorRoundId = uint64(_roundId);

        return (phaseId, aggregatorRoundId);
    }

    /** to fetch closest round id at specific timestamp from chainlink
     * parameters:
     * initial round id : roundID
     * inital timestamp : last_timestamp
     * specific timestamp : target_timeStamp
     * return closest roundid to the target timestamp : target_timeStamp
     */
    function fetch_closest_roundID_to_timestamp_by_time_difference_v1(
        uint80 roundID,
        uint last_timeStamp,
        uint target_timeStamp
    ) public view returns (uint80) {
        uint80 next_roundID = roundID;
        uint80 new_roundID;
        bool found = false;
        int next_price;
        uint next_timeStamp = last_timeStamp;
        uint80 _init_deduction = _deduction;

        // if current time and end_time is less than 1 hours, 23 minutes and 20 seconds., use v1 algorithm
        while (found == false) {
            (next_price, next_timeStamp) = getHistoricalPrice(next_roundID);

            if (next_timeStamp > 0 && next_price > 0) {
                if (next_timeStamp > target_timeStamp) {
                    //calculate timestamp difference
                    uint timestamp_difference = next_timeStamp -
                        target_timeStamp;

                    if (timestamp_difference < _ini_timestamp_difference) {
                        found = true;
                        break;
                    } else {
                        new_roundID = next_roundID;
                        next_roundID = next_roundID - _init_deduction;
                    }
                } else {
                    if (_init_deduction >= 10) {
                        _init_deduction = _init_deduction / 10;
                        next_roundID = new_roundID - _init_deduction;
                    } else {
                        found = true;
                        break;
                    }
                }
            } else {
                next_roundID = next_roundID - _init_deduction / 2;
            }
        }

        return next_roundID;
    }

    /**
     * to fetch the price from ChainLink price feed of specified timeStamp
     * parameters:
     * pair_name : pair name of ens address in the ChainLink_Price_Feed_Contract_Addresses.
     * timeStamp:preffered timestamp.
     * token_decimails:token_decimails of supported ERC20 token
     * returns:
     * priceFeed.getRoundData() object by roundId
     * int256 price.
     * uint80 timeStamp.
     */
    function fetch_closest_price_to_timestamp(
        string calldata pair_name,
        uint timeStamp,
        uint token_decimails
    ) public returns (uint256, uint80) {
        set_ENS_address(pair_name);

        uint80 roundID;
        int price;
        uint startedAt;
        uint last_timeStamp;
        uint80 answeredInRound;
        uint _token_decimails = token_decimails;

        /*first get roundID of last price*/
        (
            roundID,
            price,
            startedAt,
            last_timeStamp,
            answeredInRound
        ) = getLatestPrice();

        /*use roundID of last price to find old data*/
        bool found = false;
        uint80 next_roundID = roundID;
        uint ENS_address_decimails;

        int next_price;
        uint next_timeStamp;
        uint target_timeStamp = timeStamp;

        uint _time_different = block.timestamp - target_timeStamp;

        if (_time_different >= _ini_timestamp_difference) {
            next_roundID = fetch_closest_roundID_to_timestamp_by_time_difference_v1(
                roundID,
                last_timeStamp,
                target_timeStamp
            );
        }

        // if current time and end_time is less than 1 hours, 23 minutes and 20 seconds., use v1 algorithm
        while (found == false) {
            (next_price, next_timeStamp) = getHistoricalPrice(next_roundID);

            target_price = next_price;
            target_roundID = next_roundID;

            /*find the smallest timestamp_difference, means closest timestamp to the target*/
            if (
                next_timeStamp <= target_timeStamp &&
                next_timeStamp > 0 &&
                next_price > 0
            ) {
                ENS_address_decimails = pair_name_in_contract_addresses[
                    current_ContractAddresses_Id
                ].ENS_address_decimails;
                found = true;
                break;
            }

            next_roundID--;
        }

        /* calculates correct deciamls */
        uint correct_decimals = _token_decimails - ENS_address_decimails;
        returned_target_price = uint(target_price) * (10 ** correct_decimals);

        return (returned_target_price, target_roundID);
    }
}
