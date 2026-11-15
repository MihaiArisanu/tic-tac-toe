#!/bin/bash

TUNNEL_PID_FILE="/tmp/tictactoe_tunnel.pid"
TUNNEL_LOG="/tmp/tictactoe_tunnel.log"

sudo systemctl start apache2 tictactoe

if [[ -f "$TUNNEL_PID_FILE" ]] && kill -0 "$(cat "$TUNNEL_PID_FILE")" 2>/dev/null; then
    echo "Services and tunnel are already running."
    exit 0
fi

nohup ssh -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes -N -R tictactoe-mihai:80:localhost:80 serveo.net > "$TUNNEL_LOG" 2>&1 &
echo $! > "$TUNNEL_PID_FILE"

sleep 2
echo "Server started: https://tictactoe-mihai.serveousercontent.com"
