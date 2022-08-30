// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract ChessLib {

    Piece[64] private board;

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

    constructor() {
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

    function getInitBoard() external view returns (Piece[64] memory) {
        return board;
    }
}