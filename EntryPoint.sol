// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./ChessBoard.sol";
import "./Bank.sol";

contract EntryPoint {

    uint256 constant public GAME_COST           =   1 ether;
    uint256 constant public GAME_TIMEOUT_COST   = 100 gwei;
    uint256 constant public REVEAL_TIMEOUT_COST = 100 gwei;

    struct Pairing {
        address playerA;
        address playerB;
        bytes32 secretA;
        bytes32 secretB;
        bool    colorA;
        bool    colorB;
        bool    revealedA;
        bool    revealedB;
        uint256 timer;
    }

    address public bankAddress = address(new Bank());
    address public lastPlayer  = address(0x0);

    mapping(address => Pairing) private pairings;

    event CommitmentA(address player);
    event RevealStageStarted(address playerA, address playerB);
    event Uncommit();
    event Reveal(address playerA, address playerB, bool isWhite, bool isPlayerA);
    event NewGame(address white, address black, address contractAddress);
    event RevealTimeout(address playerA, address playerB);

    function commit(bytes32 secret) public payable {
        require(msg.value == (GAME_COST + REVEAL_TIMEOUT_COST + GAME_TIMEOUT_COST) / 2);
        require(pairings[msg.sender].playerA == address(0x0));
        require(pairings[msg.sender].playerA != msg.sender);

        if (lastPlayer == address(0x0)) {
            pairings[msg.sender] = Pairing(msg.sender, address(0x0), secret, 0x0, false, false, false, false, 0);
            lastPlayer           = msg.sender;
            
            emit CommitmentA(msg.sender);
        } else {
            pairings[lastPlayer].playerB = msg.sender;
            pairings[lastPlayer].secretB = secret;
            pairings[lastPlayer].timer   = block.number;
            pairings[msg.sender]         = pairings[lastPlayer];

            lastPlayer = address(0x0);

            emit RevealStageStarted(pairings[lastPlayer].playerA, pairings[lastPlayer].playerB);
        }

        (bool success,) = bankAddress.call{value: msg.value}("");
        require(success);
    }

    function uncommit() public {
        require(pairings[msg.sender].playerA == msg.sender);
        require(pairings[msg.sender].playerB == address(0x0));
        
        delete pairings[msg.sender];

        lastPlayer = address(0x0);

        require(Bank(payable(bankAddress)).assignRefund(msg.sender, (GAME_COST + REVEAL_TIMEOUT_COST + GAME_TIMEOUT_COST) / 2));

        emit Uncommit();
    }

    function reveal(bytes32 nonce, bool isWhite) public {
        require(pairings[msg.sender].playerB != address(0x0));

        uint256 difference = block.number - pairings[msg.sender].timer;
        address playerA    = pairings[msg.sender].playerA;
        address playerB    = pairings[msg.sender].playerB;

        if (difference >= 256) {
            delete pairings[playerA];
            delete pairings[playerB];

            require(Bank(payable(bankAddress)).assignRefund(playerA, (GAME_COST + REVEAL_TIMEOUT_COST + GAME_TIMEOUT_COST) / 2));
            require(Bank(payable(bankAddress)).assignRefund(playerB, (GAME_COST + REVEAL_TIMEOUT_COST + GAME_TIMEOUT_COST) / 2));

            emit RevealTimeout(playerA, playerB);

            return;
        } else {
            require(difference > 0);
        }

        bool isPlayerA = pairings[msg.sender].playerA == msg.sender;

        if (isPlayerA) {
            require(keccak256(abi.encodePacked(nonce, msg.sender, isWhite)) == pairings[msg.sender].secretA);
            pairings[playerA].colorA    = isWhite;
            pairings[playerB].colorA    = isWhite;
            pairings[playerA].revealedA = true;
            pairings[playerB].revealedA = true;
        } else {
            require(keccak256(abi.encodePacked(nonce, msg.sender, isWhite)) == pairings[msg.sender].secretB);
            pairings[playerA].colorB    = isWhite;
            pairings[playerB].colorB    = isWhite;
            pairings[playerA].revealedB = true;
            pairings[playerB].revealedB = true;
        }

        emit Reveal(playerA, playerB, isWhite, isPlayerA);

        if (pairings[msg.sender].revealedA && pairings[msg.sender].revealedA) {
            address white;
            address black;

            if (pairings[msg.sender].colorA != pairings[msg.sender].colorB) {
                if (pairings[msg.sender].colorA) {
                    white = playerA;
                    black = playerB;
                } else {
                    white = playerB;
                    black = playerA;
                }
            } else {
                bytes32 colorRep = 0x0;

                if (isWhite) {
                    colorRep = ~colorRep;
                }

                bool random = uint256(colorRep ^ blockhash(pairings[msg.sender].timer + 1)) % 2 == 0;

                if (random) {
                    white = playerB;
                    black = playerA;
                } else {
                    white = playerA;
                    black = playerB;
                }
            }

            ChessBoard game = new ChessBoard(white, black, bankAddress);

            require(Bank(payable(bankAddress)).addAuthorizedAddress(address(game)));

            emit NewGame(white, black, address(game));
            
            delete pairings[playerA];
            delete pairings[playerB];

            if (playerA == msg.sender) {
                require(Bank(payable(bankAddress)).assignRefund(playerB, (REVEAL_TIMEOUT_COST / 2)));
            } else {
                require(Bank(payable(bankAddress)).assignRefund(playerA, (REVEAL_TIMEOUT_COST / 2)));
            }
            require(Bank(payable(bankAddress)).assignRefund(msg.sender, (GAME_COST + REVEAL_TIMEOUT_COST / 2)));
        }
    }

    function forceTimeout() public {
        require(pairings[msg.sender].timer != 0);
        require(block.number - pairings[msg.sender].timer > 40);

        address playerA = pairings[msg.sender].playerA;
        address playerB = pairings[msg.sender].playerB;

        delete pairings[playerA];
        delete pairings[playerB];

        if (msg.sender == playerA) {
            require(Bank(payable(bankAddress)).assignRefund(playerB, (GAME_COST + GAME_TIMEOUT_COST) / 2));
        } else {
            require(Bank(payable(bankAddress)).assignRefund(playerA, (GAME_COST + GAME_TIMEOUT_COST) / 2));
        }
        require(Bank(payable(bankAddress)).assignRefund(msg.sender, REVEAL_TIMEOUT_COST + (GAME_COST + GAME_TIMEOUT_COST) / 2));

        emit RevealTimeout(playerA, playerB);
    }

}