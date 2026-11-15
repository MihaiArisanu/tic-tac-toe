#!/bin/bash

SQLITE_DB="${DATA_DIR:-/home/mihai/tictactoe/data}/tictactoe.sqlite"

db_init() {
    sqlite3 "$SQLITE_DB" << 'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
    username TEXT PRIMARY KEY,
    password TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS games (
    game_id TEXT PRIMARY KEY,
    board TEXT NOT NULL,
    status TEXT NOT NULL,
    turn TEXT NOT NULL,
    player_x TEXT NOT NULL,
    player_o TEXT DEFAULT '',
    winner TEXT DEFAULT '-',
    last_activity INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS match_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    game_id TEXT NOT NULL,
    player_x TEXT NOT NULL,
    player_o TEXT NOT NULL,
    winner TEXT NOT NULL,
    finished_at INTEGER NOT NULL
);
SQL
}

db_create_game() {
    local gid="$1" px="$2" now="$3"
    sqlite3 "$SQLITE_DB" << SQL
.param init
.param set :gid '$gid'
.param set :px '$px'
.param set :now $now
INSERT INTO games (game_id, board, status, turn, player_x, last_activity)
VALUES (:gid, '---------', 'WAITING', 'X', :px, :now);
SQL
}

db_get_state() {
    local gid="$1"
    sqlite3 -separator '|' "$SQLITE_DB" << SQL
.param init
.param set :gid '$gid'
SELECT board, status, turn, winner, player_x, player_o, last_activity
FROM games WHERE game_id = :gid;
SQL
}

db_update_move() {
    local gid="$1" board="$2" status="$3" turn="$4" winner="$5" now="$6"
    sqlite3 "$SQLITE_DB" << SQL
.param init
.param set :gid '$gid'
.param set :board '$board'
.param set :status '$status'
.param set :turn '$turn'
.param set :winner '$winner'
.param set :now $now
UPDATE games
SET board = :board, status = :status, turn = :turn, winner = :winner, last_activity = :now
WHERE game_id = :gid;
SQL
}

db_log_history() {
    local gid="$1" px="$2" po="$3" winner="$4" now="$5"
    sqlite3 "$SQLITE_DB" << SQL
.param init
.param set :gid '$gid'
.param set :px '$px'
.param set :po '$po'
.param set :winner '$winner'
.param set :now $now
INSERT INTO match_history (game_id, player_x, player_o, winner, finished_at)
VALUES (:gid, :px, :po, :winner, :now);
SQL
}
