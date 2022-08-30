// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./Bank.sol";

contract ChessBoard {

    uint256 constant public CASTLING_COST     = 1 ether;
    uint256 constant public GAME_TIMEOUT_COST = 1000 gwei;

    address public white;
    address public black;

    bool public whiteTurn = true;

    Bank private bank;

    Piece[64] private board;

    mapping(bytes32 => uint8) private stateRepetitions;
    bool public threefoldDraw = false;

    uint8 private enPassant = 64;
    
    bool[6] private hasMoved;
    bool public leftCastlingPermitted  = true;
    bool public rightCastlingPermitted = true;
    Direction public castlingValidation = Direction.NONE;

    uint8 public piecesLeft          = 32;
    uint8 public movesWithoutCaputre = 0;

    bool public whiteDraw = false;
    bool public blackDraw = false;

    uint256 public whiteTimeBlocks = 0;
    uint256 public blackTimeBlocks = 0;
    uint256 public lastBlock;

    enum Piece {
        WHITE_PAWN,   //  0
        WHITE_ROOK,   //  1
        WHITE_KNIGHT, //  2
        WHITE_BISHOP, //  3
        WHITE_QUEEN,  //  4
        WHITE_KING,   //  5
        BLACK_PAWN,   //  6
        BLACK_ROOK,   //  7
        BLACK_KNIGHT, //  8
        BLACK_BISHOP, //  9
        BLACK_QUEEN,  // 10
        BLACK_KING,   // 11
        EMPTY         // 12
    }

    enum Direction {
        LEFT,
        NONE,
        RIGHT
    }

    enum Reason {
        CHECKMATE,
        RESIGNATION,
        WIN_ON_TIME,
        DEAD_POSITION,
        DRAW_BY_AGREEMENT,
        THREEFOLD_REPETITION,
        FIVEFOLD_REPETITION,
        FIFTY_MOVE_RULE,
        SEVENTY_FIVE_MOVE_RULE
    }

    event Move(bool isWhite, uint8 startRow, uint8 startColumn, uint8 endRow, uint8 endColumn, Piece piece);
    event Capture(bool isWhite, uint8 row, uint8 column, Piece piece);
    event Promotion(bool isWhite, uint8 row, uint8 column, Piece piece);
    event CastlingAttempt(bool isWhite, Direction direction);
    event CastlingFailure(bool isWhite, Direction direction);
    event CastlingSuccess(bool isWhite, Direction direction);
    event Win(address winner, Reason reason);
    event Draw(Reason reason);
    event FiftyMoveRuleDrawEnabled();
    event ThreefoldRepetitionDrawEnabled();
    event DrawProposal(address proposer);
    event DrawOfferCanceled(address canceler);

    constructor(address whitePlayer, address blackPlayer, address bankAddress) {
        white     = whitePlayer;
        black     = blackPlayer;
        bank      = Bank(payable(bankAddress));
        lastBlock = block.number;

        initBoard();

        stateRepetitions[keccak256(abi.encodePacked(board))] = 1;
    }

    modifier isPlayer() {
        require(msg.sender == white || msg.sender == black);
        _;
    }

    modifier isTurn() {
        require((msg.sender == white && whiteTurn) || (msg.sender == black && !whiteTurn));
        _;
    }

    modifier isNotCastlingMode() {
        require(castlingValidation == Direction.NONE);
        _;
    }

    function initBoard() private {
        board[0] = Piece.WHITE_ROOK;
        board[1] = Piece.WHITE_KNIGHT;
        board[2] = Piece.WHITE_BISHOP;
        board[3] = Piece.WHITE_QUEEN;
        board[4] = Piece.WHITE_KING;
        board[5] = Piece.WHITE_BISHOP;
        board[6] = Piece.WHITE_KNIGHT;
        board[7] = Piece.WHITE_ROOK;

        board[56] = Piece.BLACK_ROOK;
        board[57] = Piece.BLACK_KNIGHT;
        board[58] = Piece.BLACK_BISHOP;
        board[59] = Piece.BLACK_QUEEN;
        board[60] = Piece.BLACK_KING;
        board[61] = Piece.BLACK_BISHOP;
        board[62] = Piece.BLACK_KNIGHT;
        board[63] = Piece.BLACK_ROOK;

        for (uint8 i = 0; i < 8; i++) {
            board[ 8 + i] = Piece.WHITE_PAWN;
            board[48 + i] = Piece.BLACK_PAWN;
        }

        for (uint8 i = 16; i < 48; i++) {
            board[i] = Piece.EMPTY;
        } 
    }

    function makeMove(uint8 x1, uint8 y1, uint8 x2, uint8 y2) public isTurn {

        // CHECK IF TILES WITHIN BOARD
        require(x1 >= 0 && x1 <= 7);
        require(y1 >= 0 && y1 <= 7);
        require(x2 >= 0 && x2 <= 7);
        require(y2 >= 0 && y2 <= 7);

        uint8 startIdx = x1 * 8 + y1;
        uint8 endIdx   = x2 * 8 + y2;

        Piece piece = board[startIdx];

        // CHECK WE ARE MOVING A FIGURE OF RIGHT COLOR
        require(piece != Piece.EMPTY);
        require(checkFigColor(piece, true));

        int8 rowDist = int8(x2) - int8(x1);
        int8 colDist = int8(y2) - int8(y1);

        // MOVEMENT IS NECESSARY
        require(rowDist != 0 || colDist != 0);
        
        if (piece == Piece.WHITE_PAWN || piece == Piece.BLACK_PAWN) {
            require(rowDist <= 2);

            int8 num;

            if (whiteTurn) {
                num = 1;
            } else {
                num = -1;
            }

            if (abs(colDist) == 1) {

                // PAWN CAPTURE
                require(rowDist == num);

                bool isEnPassant = enPassant == endIdx;

                require((board[endIdx] != Piece.EMPTY && checkFigColor(board[endIdx], false)) || isEnPassant);

                if (isEnPassant) {
                    emit Capture(!whiteTurn, uint8(int8(x2) + num), y2, board[uint8(7 - num) / 2 * 8 + y2]);

                    board[uint8(7 - num) / 2 * 8 + y2] = Piece.EMPTY;
                    piecesLeft -= 1;

                }
            } else {
                require(colDist == 0);
                require(checkIntermediate(x1, y1, uint8(int8(x2) + num), y2, rowDist, colDist));

                if (rowDist == 2 * num) {

                    // INIT DOUBLE MOVE
                    require(2 * x1 == uint8(7 - 5 * num));

                    enPassant = uint8(int8(x2) - num) * 8 + y2;
                }
            }

            movesWithoutCaputre = 0;
        } else {
            uint8 num = uint8(piece) % 6;

            if (num == 1) {
                require(rowDist == 0 || colDist == 0);
                require(checkIntermediate(x1, y1, x2, y2, rowDist, colDist));
            } else if (num == 2) {
                require((abs(rowDist) == 1 && abs(colDist) == 2) || (abs(rowDist) == 2 && abs(colDist) == 1));
            } else if (num == 3) {
                require(abs(rowDist) == abs(colDist));
                require(checkIntermediate(x1, y1, x2, y2, rowDist, colDist));
            } else if (num == 4) {
                require((rowDist == 0) || (colDist == 0) || (abs(rowDist) == abs(colDist)));
                require(checkIntermediate(x1, y1, x2, y2, rowDist, colDist));
            } else if (num == 5) {
                require(abs(rowDist) <= 1);
                require(abs(colDist) <= 1);
            }
            require(board[endIdx] == Piece.EMPTY || checkFigColor(board[endIdx], false));
        }

        bool isTargetKing = uint8(board[endIdx]) % 6 == 5;

        if (isTargetKing && castlingValidation != Direction.NONE) {

            // CASTLING FAILED REVERSE GAME STATE
            uint8 row;

            if (whiteTurn) {
                row = 7;

                emit CastlingFailure(false, castlingValidation);
            } else {
                row = 0;

                emit CastlingFailure(true, castlingValidation);
            }

            if (castlingValidation == Direction.LEFT) {
                board[row * 8 + 2] = Piece.EMPTY;
                board[row * 8 + 3] = Piece.EMPTY;

                leftCastlingPermitted = false;
            } else {
                board[row * 8 + 5] = Piece.EMPTY;
                board[row * 8 + 6] = Piece.EMPTY;

                rightCastlingPermitted = false;
            }

            whiteTurn          = !whiteTurn;
            castlingValidation = Direction.NONE;
            lastBlock          = block.number;

            require(bank.assignRefund(msg.sender, CASTLING_COST));

            return;
        } else if (castlingValidation != Direction.NONE) {
            require(bank.assignRefund(msg.sender, CASTLING_COST));

            acceptCastling();
            return;
        } else if (isTargetKing) {

            // CHECKMATE
            if (whiteTurn) {
                emit Win(white, Reason.CHECKMATE);
            } else {
                emit Win(black, Reason.CHECKMATE);
            }

            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            finishGame();
            return;
        }

        if (board[endIdx] != Piece.EMPTY) {
            piecesLeft          -= 1;
            movesWithoutCaputre  = 0;

            emit Capture(!whiteTurn, x2, y2, board[endIdx]);
        } else {
            movesWithoutCaputre += 1;
        }

        if (piecesLeft == 2) {
            //DRAW BY DEAD POSITION
            emit Draw(Reason.DEAD_POSITION);
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            finishGame();
            return;
        }

        if (movesWithoutCaputre >= 75) {
            // DRAW BY 75 NON CAPTURE MOVES
            emit Draw(Reason.SEVENTY_FIVE_MOVE_RULE);
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            finishGame();
            return;
        } else if (movesWithoutCaputre == 50) {
            emit FiftyMoveRuleDrawEnabled();
        }

        board[startIdx] = Piece.EMPTY;
        board[endIdx  ] = piece;
        whiteTurn       = !whiteTurn;

        emit Move(!whiteTurn, x1, y1, x2, y2, piece);

        bytes32 stateHash = keccak256(abi.encodePacked(board));

        if (stateRepetitions[stateHash] >= 4) {
            // FIVEFOLD DRAW
            emit Draw(Reason.FIVEFOLD_REPETITION);
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            finishGame();
            return;
        } else if (stateRepetitions[stateHash] == 2) {
            // ENABLE DRAW BY THREEFOLD
            threefoldDraw = true;

            emit ThreefoldRepetitionDrawEnabled();
        } 

        stateRepetitions[stateHash] += 1;

        // RESET EN PASSANT
        if (uint8(piece) % 6 != 0 || abs(rowDist) != 2) {
            enPassant = 64;
        }

        if ((x1 == 0 && y1 == 0) || (x2 == 0 && y2 == 0)) {
            hasMoved[0] = true;
        } else if (x1 == 0 && y1 == 4) {
            hasMoved[1] = true;
        } else if ((x1 == 0 && y1 == 7) || (x2 == 0 && y2 == 7)) {
            hasMoved[2] = true;
        } else if ((x1 == 7 && y1 == 0) || (x2 == 7 && y2 == 0)) {
            hasMoved[3] = true;
        } else if (x1 == 7 && y1 == 4) {
            hasMoved[4] = true;
        } else if ((x1 == 7 && y1 == 7) || (x2 == 7 && y2 == 7)) {
            hasMoved[5] = true;
        }

        leftCastlingPermitted  = true;
        rightCastlingPermitted = true;

        checkTime();
    }

    function promotion(uint8 x, uint8 y, Piece piece) public {
        uint8 idx        = 8 * x + y;
        uint8 num        = uint8(piece) % 6;
        uint8 whitePiece = uint8(board[idx]) / 6;

        require(num >= 1 && num <= 4);
        require(uint8(board[idx]) % 6 == 0);
        require(board[idx] != Piece.EMPTY);
        require((x == 7 && whitePiece == 0 && msg.sender == white) || (x == 0 && whitePiece == 1 && msg.sender == black));

        board[idx] = piece;

        if (msg.sender == white) {
            emit Promotion(true, x, y, piece);
        } else {
            emit Promotion(false, x, y, piece);
        }
    }

    function castling(bool isLeft) public payable isTurn isNotCastlingMode {
        require(msg.value == CASTLING_COST);

        checkTime();

        (bool success,) = address(bank).call{value: msg.value}("");
        require(success);

        if (whiteTurn) {
            require(!hasMoved[1]);

            if (isLeft) {
                require(!hasMoved[0] && leftCastlingPermitted);
                require(checkIntermediate(0, 4, 0, 0, 0, -4));

                board[2] = Piece.WHITE_KING;
                board[3] = Piece.WHITE_KING;

                castlingValidation = Direction.LEFT;
            } else {
                require(!hasMoved[2] && rightCastlingPermitted);
                require(checkIntermediate(0, 4, 0, 7, 0, 3));

                board[5] = Piece.WHITE_KING;
                board[6] = Piece.WHITE_KING;

                castlingValidation = Direction.RIGHT;
            }

            emit CastlingAttempt(true, castlingValidation);
        } else {
            require(!hasMoved[4]);

            if (isLeft) {
                require(!hasMoved[3] && leftCastlingPermitted);
                require(checkIntermediate(7, 4, 7, 0, 0, -4));

                board[58] = Piece.BLACK_KING;
                board[59] = Piece.BLACK_KING;

                castlingValidation = Direction.LEFT;
            } else {
                require(!hasMoved[5] && rightCastlingPermitted);
                require(checkIntermediate(7, 4, 7, 7, 0, 3));

                board[61] = Piece.BLACK_KING;
                board[62] = Piece.BLACK_KING;

                castlingValidation = Direction.RIGHT;
            }

            emit CastlingAttempt(false, castlingValidation);
        }
        
        whiteTurn = !whiteTurn;
    }

    function acceptCastling() private {
        // CASTLING SUCCEEDED
        if (whiteTurn) {
            if (castlingValidation == Direction.LEFT) {
                board[48] = Piece.EMPTY;
                board[51] = Piece.BLACK_ROOK;
            } else {
                board[63] = Piece.EMPTY;
                board[61] = Piece.BLACK_ROOK;
            }

            board[60] = Piece.EMPTY;

            hasMoved[3] = true;
            hasMoved[4] = true;
            hasMoved[5] = true;

            emit CastlingSuccess(true, castlingValidation);
        } else {
            if (castlingValidation == Direction.LEFT) {
                board[0] = Piece.EMPTY;
                board[3] = Piece.WHITE_ROOK;
            } else {
                board[7] = Piece.EMPTY;
                board[5] = Piece.WHITE_ROOK;
            }

            board[4] = Piece.EMPTY;

            hasMoved[0] = true;
            hasMoved[1] = true;
            hasMoved[2] = true;

            emit CastlingSuccess(false, castlingValidation);
        }

        castlingValidation      = Direction.NONE;
        leftCastlingPermitted   = true;
        rightCastlingPermitted  = true;
        movesWithoutCaputre    += 1;
        lastBlock               = block.number;
    }

    function castlingTimeout() public {
        require(block.number - lastBlock < 40);
        if (whiteTurn) {
            require(bank.assignRefund(black, CASTLING_COST));
        } else {
            require(bank.assignRefund(white, CASTLING_COST));
        }
        acceptCastling();
    }

    function resign() public isPlayer isNotCastlingMode {
        require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
        require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));

        if (msg.sender == white) {
            emit Win(black, Reason.RESIGNATION);
        } else {
            emit Win(white, Reason.RESIGNATION);
        }
        finishGame();
    }

    function forceTimeout() public isPlayer isNotCastlingMode {
        require((msg.sender == white && !whiteTurn) || (msg.sender == black && whiteTurn));
        
        if (whiteTurn) {
            require(block.number - lastBlock + whiteTimeBlocks > 400);
            require(bank.assignRefund(msg.sender, GAME_TIMEOUT_COST));

            // BLACK WINS BY TIMEOUT
            emit Win(black, Reason.WIN_ON_TIME);
            finishGame();
        } else {
            require(block.number - lastBlock + blackTimeBlocks > 400);
            require(bank.assignRefund(msg.sender, GAME_TIMEOUT_COST));

            // WHITE WINS BY TIMEOUT
            emit Win(white, Reason.WIN_ON_TIME);
            finishGame();
        }
    }

    function drawByAgreement() public isPlayer isNotCastlingMode {
        if (movesWithoutCaputre >= 50) {
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            emit Draw(Reason.FIFTY_MOVE_RULE);
            finishGame();
            return;
        } else if (threefoldDraw) {
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            emit Draw(Reason.THREEFOLD_REPETITION);
            finishGame();
            return;
        }

        if (msg.sender == white) {
            whiteDraw = true;
        } else {
            blackDraw = true;
        }

        emit DrawProposal(msg.sender);

        if (whiteDraw && blackDraw) {
            require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
            require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
            emit Draw(Reason.DRAW_BY_AGREEMENT);
            finishGame();
        }
    }

    function cancelDraw() public isPlayer {
        if (msg.sender == white) {
            whiteDraw = false;
            emit DrawOfferCanceled(white);
        } else {
            blackDraw = false;
            emit DrawOfferCanceled(black);
        }
    }

    function checkFigColor(Piece piece, bool shouldBeSame) private view returns (bool) {
        uint8 whitePiece = uint8(piece) / 6;
        bool  areSame    = (whitePiece == 0 && whiteTurn) || (whitePiece == 1 && !whiteTurn);

        return (areSame && shouldBeSame) || (!areSame && !shouldBeSame);
    }

    function checkIntermediate(uint8 x1, uint8 y1, uint8 x2, uint8 y2, int8 rowDist, int8 colDist) private view returns (bool) {
        uint8 rowIdx = x1;
        uint8 colIdx = y1;

        while (true) {
            if (rowDist < 0) {
                rowIdx -= 1;
            } else if (rowDist > 0) {
                rowIdx += 1;
            }

            if (colDist < 0) {
                colIdx -= 1;
            } else if (colDist > 0) {
                colIdx += 1;
            }

            if (rowIdx == x2 && colIdx == y2) {
                break;
            }
            
            require(board[rowIdx * 8 + colIdx] == Piece.EMPTY);
        }

        return true;
    }

    function checkTime() private isNotCastlingMode {
        uint256 difference = block.number - lastBlock;

        if (whiteTurn) {
            whiteTimeBlocks += difference;

            if (whiteTimeBlocks > 400) {
                require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
                require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));

                // BLACK WINS BY TIMEOUT
                emit Win(black, Reason.WIN_ON_TIME);
                finishGame();
            }
        } else {
            blackTimeBlocks += difference;

            if (blackTimeBlocks > 400) {
                require(bank.assignRefund(black, GAME_TIMEOUT_COST / 2));
                require(bank.assignRefund(white, GAME_TIMEOUT_COST / 2));
                
                // WHITE WINS BY TIMEOUT
                emit Win(white, Reason.WIN_ON_TIME);
                finishGame();
            }
        }

        lastBlock = block.number;
    }

    function abs(int8 x) private pure returns (int8) {
        return x >= 0 ? x : -x;
    }

    function finishGame() private {
        require(bank.deleteAuthorizedAddress());
        selfdestruct(payable(bank));
    }

}