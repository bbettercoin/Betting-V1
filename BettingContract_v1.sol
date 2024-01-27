// SPDX-License-Identifier: BUSL-1.1
//version 1.1
//BettingContract for https://bbetter.co.in/

//BSC TESTNET
//0x4Af3ef2309A9B703Db673af6fE3f784eE20f72Fe brav ac2
//0x393BBf911E5624b91C9AA6Ead47a7f7f7C369809 fire ac2

//BSC MAINNET

pragma solidity ^0.8.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/ERC20.sol";

import "https://github.com/bbettercoin/Betting-V1/blob/main/BettingOracle_ChainLink_v3.sol";

//import "./BettingOracle_ChainLink_v3-1.sol";

contract BettingContract_v1 {
    address public developer;

    //init better_oracle
    BettingOracle_ChainLink_v3 public better_oracle;

    struct Bet {
        uint256 bet_id;
        uint256 betting_id;
        address user;
        uint256 predictedPrice;
        uint256 amount;
        bool winner;
        bool claimed;
        bool rebeted;
        uint256 winningsRatio;
        uint256 winningsAmount;
    }

    enum Status {
        Open,
        Pending,
        Closed
    }

    Status constant default_value = Status.Open;

    struct Betting {
        uint256 id;
        string pair_name;
        address betting_token;
        address creater;
        uint256 startTime;
        uint256 endTime;
        uint256 pendingTime;
        uint256 correctPrice;
        uint256 totalBets;
        uint256 totalAmount;
        Status status;
        bool hadWinner;
    }

    uint256 public bettingCount;
    uint256 public betCount;
    mapping(uint256 => Betting) public bettings;
    mapping(uint256 => Bet) public bets;

    event BettingCreated(
        uint256 id,
        string pair_name,
        address betting_token,
        address creater,
        uint256 startTime,
        uint256 endTime,
        uint256 pendingTime,
        bool hadWinner
    );
    event BetPlaced(
        uint256 bet_id,
        uint256 betting_id,
        address user,
        uint256 predictedPrice,
        uint256 amount,
        bool winner,
        bool claimed,
        bool rebeted,
        uint256 winningsRatio,
        uint256 winningsAmount
    );
    event BettingClosed(uint256 id, uint256 correctPrice);
    event WinningClaimed(address user, uint256 amount);

    //timeLeap
    //1209600 = 14 days
    //604800 = 7 days
    //1080 = 18 minutes
    //720 = 12 minutes
    //360 = 6 minutes
    //60 = 1 minute

    uint256 timeLeap_start = 60;
    uint256 public timeLeap_end;
    uint256 public timeLeap_pending;

    uint256 public fee_percentage; // 4 = 4%
    uint256 public range_percentage; // 6 = 6%
    uint256 ratio_decimails; //10 ** 18 = 1000000000000000000

    address oracle_address;

    constructor(
        uint256 in_timeLeap_end,
        uint256 in_timeLeap_pending,
        uint256 in_fee_percentage,
        uint256 in_range_percentage,
        uint256 in_ratio_decimails,
        address _oracle_address
    ) {
        developer = msg.sender;
        timeLeap_end = in_timeLeap_end;
        timeLeap_pending = in_timeLeap_pending;

        fee_percentage = in_fee_percentage;
        range_percentage = in_range_percentage;
        ratio_decimails = in_ratio_decimails;

        better_oracle = BettingOracle_ChainLink_v3(_oracle_address);
    }

    /**
     * to re construct the build
     */
    function update_constructor(
        uint256 in_timeLeap_end,
        uint256 in_timeLeap_pending,
        uint256 in_fee_percentage,
        uint256 in_range_percentage,
        uint256 in_ratio_decimails,
        address _oracle_address
    ) public {
        require(developer == msg.sender, "only developer can update timeLeap");

        timeLeap_end = in_timeLeap_end;
        timeLeap_pending = in_timeLeap_pending;

        fee_percentage = in_fee_percentage;
        range_percentage = in_range_percentage;
        ratio_decimails = in_ratio_decimails;

        better_oracle = BettingOracle_ChainLink_v3(_oracle_address);
    }

    /**
     * main function
     * to create Betting for Bet
     * endTime means due time of predict price
     */
    function CreateBetting(
        string calldata pair_name,
        address betting_token,
        uint256 endTime
    ) public returns (uint256) {
        uint256 startTime = block.timestamp + timeLeap_start;

        require(
            startTime >= block.timestamp,
            "Betting cannot start in the past @ CreateBetting()"
        );

        uint256 check_endTime = endTime - timeLeap_end;
        require(
            check_endTime > startTime,
            "Invalid end time (endTime < startTime) @ CreateBetting()"
        );

        uint256 pendingTime = endTime - timeLeap_pending;
        require(
            pendingTime > startTime,
            "Invalid pending time (pendingTime < startTime) @ CreateBetting()"
        );

        address creater = msg.sender;
        bettingCount++;

        (, , bool valid) = better_oracle
            .fetch_betting_token_from_ChainLink_Price_Feed_Contract_Addresses_obj(
                pair_name
            );

        require(valid == true, "pair_name not supported! @ CreateBetting()");

        Betting storage newBetting = bettings[bettingCount];
        newBetting.pair_name = pair_name;
        newBetting.betting_token = betting_token;
        newBetting.creater = creater;
        newBetting.id = bettingCount;
        newBetting.startTime = startTime;
        newBetting.endTime = endTime;
        newBetting.pendingTime = pendingTime;
        newBetting.correctPrice = 0;
        newBetting.totalBets = 0;
        newBetting.totalAmount = 0;
        newBetting.status = Status.Open;
        newBetting.hadWinner = false;

        emit BettingCreated(
            bettingCount,
            pair_name,
            betting_token,
            creater,
            startTime,
            endTime,
            pendingTime,
            false
        );

        return bettingCount;
    }

    /**
     * private function
     * to add bet list
     */
    function _BetPlaced(
        uint256 betting_id,
        uint256 predictedPrice,
        uint256 amount
    ) private returns (uint256) {
        (
            uint256 bet_id_in_current_betting_id,
            uint256 bet_id_in_all_bet_list
        ) = bet_id_by_user(betting_id, msg.sender);
        require(bet_id_in_all_bet_list == 0, "wrong betting id @ _BetPlaced()");
        require(
            bet_id_in_current_betting_id == 0,
            "You already bed on this betting! @ _BetPlaced()"
        );

        uint256 total_fee = FeeCollector(betting_id, amount);

        uint256 new_bet_amount = amount - total_fee;

        betCount++;

        uint256 currrent_bet_length = bet_length(betting_id);
        uint256 new_bet_id = currrent_bet_length + 1;

        bettings[betting_id].totalBets++;
        bettings[betting_id].totalAmount += new_bet_amount;

        Bet storage newBet = bets[betCount];
        newBet.bet_id = new_bet_id;
        newBet.betting_id = betting_id;
        newBet.user = msg.sender;
        newBet.predictedPrice = predictedPrice;
        newBet.amount = new_bet_amount;
        newBet.winner = false;
        newBet.claimed = false;
        newBet.rebeted = false;
        newBet.winningsRatio = 0;
        newBet.winningsAmount = 0;

        emit BetPlaced(
            new_bet_id,
            betting_id,
            msg.sender,
            predictedPrice,
            amount,
            false,
            false,
            false,
            0,
            0
        );

        return betCount;
    }

    /**
     * main function
     * to create Bets
     */
    function CreateBet(
        address betting_token,
        uint256 betting_id,
        uint256 predictedPrice,
        uint256 amount
    ) public payable returns (uint256) {
        /*
        require(
            keccak256(bytes(bettings[betting_id].pair_name)) == keccak256(bytes(pair_name)),
            "incompatible token address @ CreateBet()"
        );
        
        require(
            betting_id > 0 && betting_id <= bettingCount,
            "Invalid betting ID @ CreateBet()"
        );
        */
        require(
            bettings[betting_id].status == Status.Open,
            "Betting is not open for bets @ CreateBet()"
        );
        require(
            block.timestamp < bettings[betting_id].pendingTime,
            "Betting is closed for new bets @ CreateBet()"
        );
        require(amount > 0, "Invalid bet amount @ CreateBet()");

        IERC20 token = IERC20(betting_token);
        require(
            token.balanceOf(msg.sender) >= amount,
            "Insufficient token balance @ CreateBet()"
        );
        require(
            token.approve(address(this), amount),
            "Not approving token transfer! @ CreateBet()"
        );
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed @ CreateBet()"
        );

        return _BetPlaced(betting_id, predictedPrice, amount);
    }

    /**
     * all betters can close betting if betting is passing pending time
     * loop current betting by betting id to calculate winners
     */
    function CloseBetting(uint256 _betting_id) public {
        (, uint256 bet_id_in_all_bet_list) = bet_id_by_user(
            _betting_id,
            msg.sender
        );

        bool bettor = false;
        Betting storage betting = bettings[_betting_id];

        if (
            bets[bet_id_in_all_bet_list].betting_id == _betting_id &&
            bets[bet_id_in_all_bet_list].amount > 0
        ) {
            bettor = true;
        }

        if (bettings[_betting_id].creater == msg.sender) {
            bettor = true;
        }

        require(
            bettor == true,
            "only bettors or creater can close betting @ CloseBetting()"
        );

        require(
            betting.status == Status.Open,
            "Betting is not open @ CloseBetting()"
        );
        require(
            block.timestamp >= betting.pendingTime,
            "Betting pendingTime has not passed yet @ CloseBetting()"
        );
        require(
            block.timestamp >= betting.endTime,
            "Betting endTime has not passed yet @ CloseBetting()"
        );

        //uint256 token_decimails;
        //address oracle_address;

        // get token decimals

        (, uint256 token_decimails, ) = better_oracle
            .fetch_betting_token_from_ChainLink_Price_Feed_Contract_Addresses_obj(
                betting.pair_name
            );

        (uint256 _correctPrice, ) = better_oracle
            .fetch_closest_price_to_timestamp(
                betting.pair_name,
                betting.endTime,
                token_decimails
            );

        //to do: use oracle to replace this line
        bettings[_betting_id].correctPrice = _correctPrice;

        bool hasWinner = false;

        uint256 all_winner_bet_amount = 0;

        uint256 correct_price_range = (_correctPrice * range_percentage) / 200;

        uint256 correct_price_upper_bond = _correctPrice + correct_price_range;

        uint256 correct_price_lower_bond = _correctPrice - correct_price_range;

        //loop current betting to calculate winners
        for (uint256 i = 0; i <= betCount; i++) {
            if (bets[i].betting_id == _betting_id) {
                if (bets[i].amount != 0) {
                    // meet the price range
                    if (
                        bets[i].predictedPrice >= correct_price_lower_bond &&
                        bets[i].predictedPrice <= correct_price_upper_bond
                    ) {
                        bets[i].winner = true;
                        hasWinner = true;

                        all_winner_bet_amount += bets[i].amount;
                    }
                }
            }
        }

        //loop current betting to calculate winning ratio and winning amount
        if (hasWinner == true) {
            for (uint256 i = 0; i <= betCount; i++) {
                if (bets[i].betting_id == _betting_id) {
                    if (bets[i].winner == true) {
                        //uint256 winnings_ratio = (bets[i].amount * ratio_decimails )/ all_winner_bet_amount;

                        //bets[i].winningsRatio = (bets[i].amount * ratio_decimails )/ all_winner_bet_amount;
                        //bets[i].winningsAmount = (((bets[i].amount * ratio_decimails )/ all_winner_bet_amount) * (bettings[_betting_id].totalAmount - all_winner_bet_amount)) / ratio_decimails;
                        bets[i].winningsRatio = calculate_winningsRatio(
                            i,
                            all_winner_bet_amount
                        );
                        bets[i].winningsAmount = calculate_winningsAmount(
                            _betting_id,
                            i,
                            all_winner_bet_amount
                        );
                    }
                }
            }
        }

        //betting is closed, waiting for user to claim winnings
        betting.status = Status.Pending;
        betting.hadWinner = hasWinner;
    }

    /**
     * calculate_winningsRatio for CloseBetting(uint256 _betting_id)
     */
    function calculate_winningsRatio(
        uint256 bet_id,
        uint256 all_winner_bet_amount
    ) private view returns (uint256) {
        return (bets[bet_id].amount * ratio_decimails) / all_winner_bet_amount;
    }

    /**
     * calculate_winningsAmount for CloseBetting(uint256 _betting_id)
     */
    function calculate_winningsAmount(
        uint256 _betting_id,
        uint256 bet_id,
        uint256 all_winner_bet_amount
    ) private view returns (uint256) {
        return
            (((bets[bet_id].amount * ratio_decimails) / all_winner_bet_amount) *
                (bettings[_betting_id].totalAmount - all_winner_bet_amount)) /
            ratio_decimails;
    }

    /**
     * if betting has no winners, all better can not claims
     * if betting has winner, only winners can claims
     */
    function WinningClaims(address betting_token, uint256 _bettingId) public {
        (
            uint256 bet_id_in_current_betting_id,
            uint256 bet_id_in_all_bet_list
        ) = bet_id_by_user(_bettingId, msg.sender);

        require(
            bet_id_in_all_bet_list > 0,
            "wrong bet id in bet list @ WinningClaims()"
        );
        require(
            bet_id_in_current_betting_id > 0,
            "wrong bet id in betting list @ WinningClaims()"
        );
        require(
            bets[bet_id_in_all_bet_list].betting_id == _bettingId,
            "wrong betting id @ WinningClaims()"
        );
        /*
        require(
            bettings[_bettingId].status == Status.Pending,
            "Betting is not pending @ WinningClaims()"
        );
        */

        require(
            bettings[_bettingId].hadWinner == true,
            "This betting has no winner. @ WinningClaims()"
        );

        require(
            bets[bet_id_in_all_bet_list].user == msg.sender,
            "You did not bet on this betting. @ WinningClaims()"
        );
        require(
            bets[bet_id_in_all_bet_list].winner == true,
            "You did not win over this bet. @ WinningClaims()"
        );

        uint256 winnings = bets[bet_id_in_all_bet_list].winningsAmount;
        uint256 bet_amount = bets[bet_id_in_all_bet_list].amount;
        uint256 transfer_amount = winnings + bet_amount;
        /*
        require(
            transfer_amount > 0,
            "Your winning amount is zero. @ WinningClaims()"
        );
        */
        require(
            bets[bet_id_in_all_bet_list].claimed == false,
            "You have already claimed your winnings. @ WinningClaims()"
        );
        require(
            bets[bet_id_in_all_bet_list].rebeted == false,
            "You have already rebeted your winnings. @ WinningClaims()"
        );

        if (transfer_amount > 0) {
            IERC20 token = IERC20(betting_token);

            token.transfer(msg.sender, transfer_amount);

            bets[bet_id_in_all_bet_list].claimed = true;

            emit WinningClaimed(msg.sender, transfer_amount);
        }
    }

    /**
     * if betting has no winners, all better can rebet
     * if betting has winner, only winners can rebet
     */
    function ReBet(
        address betting_token,
        uint256 _originalbetting_bettingId,
        uint256 _newbetting_bettingId,
        uint256 predictedPrice
    ) public returns (bool) {
        (
            uint256 bet_id_in_current_betting_id,
            uint256 bet_id_in_all_bet_list
        ) = bet_id_by_user(_originalbetting_bettingId, msg.sender);
        require(
            bet_id_in_all_bet_list > 0,
            "wrong bet id in bet list @ ReBet()"
        );
        require(
            bet_id_in_current_betting_id > 0,
            "wrong bet id in betting list @ ReBet()"
        );
        require(
            bets[bet_id_in_all_bet_list].betting_id ==
                _originalbetting_bettingId,
            "wrong betting id @ ReBet()"
        );

        require(
            bettings[_originalbetting_bettingId].status == Status.Pending,
            "Betting is not pending @ ReBet()"
        );
        require(
            bettings[_originalbetting_bettingId].betting_token == betting_token,
            "incompatible betting_token address for _originalbetting_bettingId @ ReBet()"
        );

        require(
            bets[bet_id_in_all_bet_list].user == msg.sender,
            "You did not bet on this betting. @ ReBet()"
        );
        require(
            bets[bet_id_in_all_bet_list].claimed == false,
            "You have already claimed your winnings. @ ReBet()"
        );
        require(
            bets[bet_id_in_all_bet_list].rebeted == false,
            "You have already rebeted your winnings. @ ReBet()"
        );

        uint256 rebet_amount = 0;

        if (bettings[_originalbetting_bettingId].hadWinner == true) {
            require(
                bets[bet_id_in_all_bet_list].winner == true,
                "Only winner can rebet. @ ReBet()"
            );
            //only winner can rebet
            uint256 winnings = bets[bet_id_in_all_bet_list].winningsAmount;
            uint256 bet_amount = bets[bet_id_in_all_bet_list].amount;
            rebet_amount = winnings + bet_amount;
        } else {
            // if betting has no winners, all better can rebet
            rebet_amount = bets[bet_id_in_all_bet_list].amount;
        }

        require(
            rebet_amount > 0,
            "You don't have enough amount to rebet @ ReBet()"
        );

        if (rebet_amount > 0) {
            uint256 new_bet_length = _BetPlaced(
                _newbetting_bettingId,
                predictedPrice,
                rebet_amount
            );

            if (new_bet_length > bet_id_in_all_bet_list) {
                bets[bet_id_in_all_bet_list].rebeted = true;

                return true;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    /**
     * total fee eaquals 2 times of fee_percentage for betting creater and developer
     */
    function FeeCollector(
        uint256 _bettingId,
        uint256 amount
    ) private returns (uint256) {
        address token_address = bettings[_bettingId].betting_token;

        IERC20 token = IERC20(token_address);

        uint256 fee = (amount * fee_percentage) / 100;

        address recipient = bettings[_bettingId].creater;

        //fee for betting creater
        token.transferFrom(msg.sender, recipient, fee / 2);

        //fee for developer
        token.transferFrom(msg.sender, developer, fee / 2);

        return fee;
    }

    /**
    return last uint256 key index of bet from indicated bettingId
    */
    function bet_length(uint256 _bettingId) public view returns (uint256) {
        uint256 currentBetting_bet_length = bettings[_bettingId].totalBets;

        return currentBetting_bet_length;
    }

    /**
    return uint256 key index of specific bet from indicated bettingId
    */
    function bet_id_by_user(
        uint256 _bettingId,
        address user
    ) public view returns (uint256, uint256) {
        uint256 bet_id_in_all_bet_list = 0;
        uint256 bet_id_in_current_betting_id = 0;

        for (uint256 i = 0; i <= betCount; i++) {
            if (bets[i].betting_id == _bettingId) {
                if (bets[i].user == user) {
                    bet_id_in_all_bet_list = i;
                    bet_id_in_current_betting_id = bets[i].bet_id;
                    break;
                }
            }
        }
        return (bet_id_in_current_betting_id, bet_id_in_all_bet_list);
    }

    /**
     * to render all bettings
     *
     * return Betting [] in reverse index
     * return Betting [] length
     */
    function render_bettings() public view returns (Betting[] memory, uint256) {
        Betting[] memory allBettings = new Betting[](bettingCount);

        uint256 k = 0;

        for (uint256 i = bettingCount; i > 0; i--) {
            allBettings[k] = bettings[i];
            k++;
        }

        return (allBettings, k);
    }

    /**
     * to render betting of specific betting id
     * parameter:
     * uint256 _betting_id
     * return Betting []
     */
    function render_betting_data_of_specific_betting_id(
        uint256 _betting_id
    ) public view returns (Betting[] memory) {
        Betting[] memory thisBetting = new Betting[](1);

        uint _length = bettingCount;

        for (uint256 i = _length; i > 0; i--) {
            if (bettings[i].id == _betting_id) {
                thisBetting[0] = bettings[i];
                break;
            }
        }

        return thisBetting;
    }

    /**
     * to render bettings of specific bet creater
     * parameter:
     * address _user
     * return Betting [] in reverse index
     * return Betting [] length
     */
    function render_bettings_of_specific_betting_creater(
        address _creater
    ) public view returns (Betting[] memory, uint256) {
        uint256 current_bettings_length = 0;

        uint _length = bettingCount;

        for (uint256 i = 0; i <= _length; i++) {
            if (bettings[i].creater == _creater) {
                current_bettings_length++;
            }
        }

        Betting[] memory myBettings = new Betting[](current_bettings_length);

        uint256 render_count = 0;
        uint256 k = 0;

        for (uint256 i = _length; i > 0; i--) {
            if (bettings[i].creater == _creater) {
                myBettings[k] = bettings[i];
                render_count++;
                k++;
            }

            if (render_count >= current_bettings_length) {
                break;
            }
        }

        return (myBettings, k);
    }

    /**
     * to render bets of specific betting id
     * parameter:
     * uint256 _betting_id
     * return Bet [] in reverse index
     * return Bet [] length
     */
    function render_bets_of_specific_betting_id(
        uint256 _betting_id
    ) public view returns (Bet[] memory, uint256) {
        uint256 current_bets_length = 0;

        uint _length = betCount;

        for (uint256 i = 0; i <= _length; i++) {
            if (bets[i].betting_id == _betting_id) {
                current_bets_length++;
            }
        }

        Bet[] memory allBets = new Bet[](current_bets_length);

        uint256 render_count = 0;
        uint256 k = 0;

        //for (uint256 i = _shifts; i < betCount; i++){
        for (uint256 i = _length; i > 0; i--) {
            if (bets[i].betting_id == _betting_id) {
                allBets[k] = bets[i];
                render_count++;
                k++;
            }

            if (render_count >= current_bets_length) {
                break;
            }
        }

        return (allBets, k);
    }

    /**
     * to render bets of specific bet creater
     * parameter:
     * address _user
     * return Bet [] in reverse index
     * return Bet [] length
     */
    function render_bets_of_specific_bet_creater(
        address _user
    ) public view returns (Bet[] memory, uint256) {
        uint256 current_bets_length = 0;

        uint _length = betCount;

        for (uint256 i = 0; i <= _length; i++) {
            if (bets[i].user == _user) {
                current_bets_length++;
            }
        }

        Bet[] memory allBets = new Bet[](current_bets_length);

        uint256 render_count = 0;
        uint256 k = 0;

        //for (uint256 i = _shifts; i < betCount; i++){
        for (uint256 i = _length; i > 0; i--) {
            if (bets[i].user == _user) {
                allBets[k] = bets[i];
                render_count++;
                k++;
            }

            if (render_count >= current_bets_length) {
                break;
            }
        }

        return (allBets, k);
    }
}
