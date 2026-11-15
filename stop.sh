#!/bin/bash

TUNNEL_PID_FILE="/tmp/tictactoe_tunnel.pid"

if [[ -f "$TUNNEL_PID_FILE" ]]; then
    PID=$(cat "$TUNNEL_PID_FILE")
    kill "$PID" 2>/dev/null
    rm -f "$TUNNEL_PID_FILE"
fi

pkill -f "tictactoe-mihai:80:localhost:80 serveo.net" 2>/dev/null
sudo systemctl stop tictactoe apache2

echo "All services and tunnel stopped."
