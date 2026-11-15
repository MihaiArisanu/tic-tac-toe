# Multiplayer Tic-Tac-Toe (Bash + HTML5)

Multiplayer web Tic-Tac-Toe built purely with **HTML5** (zero JavaScript) and **GNU Bash** on Linux.

## Architecture

- **Frontend (`public/`, `cgi-bin/tictactoe.cgi`)**: Minimalist black-and-white HTML5 forms with `<meta http-equiv="refresh">` polling. The CGI script never touches data files directly; it communicates exclusively over a local TCP socket.
- **Game Server Daemon (`server/server.sh`)**: Multi-process TCP server (`socat` + `fork`) managing authentication, single-session enforcement (TTL tokens), game state, and an asynchronous background cleanup worker (`60s` inactivity timeout).
- **Concurrency & Persistence (`data/`, `server/storage_sqlite.sh`)**: Synchronized file access via `flock` (`-x` / `-s`) and SQLite WAL storage module with parameterized queries.

## Setup (Debian / Ubuntu)

1. Install dependencies:
   ```bash
   sudo apt update && sudo apt install -y apache2 socat sqlite3
   sudo a2enmod cgi   
   ```
2. Configure environment:
   ```bash
   cp .env.example .env
   chmod +x cgi-bin/tictactoe.cgi server/server.sh server/storage_sqlite.sh 
   ```
3. Start the daemon and web server
   ```bash
   ./server/server.sh & sudo systemctl restart apache2
   ```
