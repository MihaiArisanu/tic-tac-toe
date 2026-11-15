#!/bin/bash

ENV_FILE="/home/mihai/tictactoe/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

HOST="${APP_HOST:-127.0.0.1}"
PORT="${APP_PORT:-9090}"

echo "Content-type: text/html"
echo ""

if [[ "$REQUEST_METHOD" == "POST" ]]; then
    read -n "$CONTENT_LENGTH" INPUT_DATA
else
    INPUT_DATA="$QUERY_STRING"
fi

get_param() {
    echo "$INPUT_DATA" | tr '&' '\n' | grep "^$1=" | head -n1 | cut -d'=' -f2- | tr -d '\r\n'
}

USER_IN=$(get_param "username")
PASS_IN=$(get_param "password")
TOKEN_IN=$(get_param "token")
ACTION_IN=$(get_param "action")
GAME_IN=$(get_param "game_id")
CELL_IN=$(get_param "cell")

send_to_server() {
    local msg="$1"
    exec 3<>/dev/tcp/"$HOST"/"$PORT" 2>/dev/null || { echo "ERR|Game server is offline"; return; }
    echo "$msg" >&3
    read -r response <&3
    exec 3<&-
    echo "$response"
}

render_header() {
    local refresh_tag="$1"
    cat << HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    $refresh_tag
    <title>Tic-Tac-Toe</title>
    <style>
        body { background: #000; color: #fff; font-family: monospace; display: flex; flex-direction: column; align-items: center; padding-top: 50px; margin: 0; }
        .box { border: 1px solid #fff; padding: 20px; width: 300px; margin-bottom: 15px; text-align: center; }
        input, button { background: #000; color: #fff; border: 1px solid #fff; padding: 8px; margin-top: 10px; width: 100%; box-sizing: border-box; font-family: monospace; }
        button { cursor: pointer; font-weight: bold; }
        button:hover:not(:disabled), a:hover { background: #fff; color: #000; }
        a { color: #fff; display: inline-block; margin-top: 15px; border: 1px solid #fff; padding: 6px 12px; text-decoration: none; }
        .board { display: grid; grid-template-columns: repeat(3, 85px); grid-template-rows: repeat(3, 85px); gap: 6px; margin: 20px 0; }
        .cell { margin: 0; padding: 0; font-size: 2em; display: flex; align-items: center; justify-content: center; }
        .cell:disabled { cursor: default; }
    </style>
</head>
<body>
    <h1>TIC-TAC-TOE</h1>
HTML
}

render_lobby() {
    local user="$1"
    local token="$2"
    render_header ""
    cat << HTML
    <p>Logged in as: <strong>$user</strong></p>
    <div class="box">
        <h3>Create Match</h3>
        <form action="/cgi-bin/tictactoe.cgi" method="POST">
            <input type="hidden" name="action" value="create">
            <input type="hidden" name="username" value="$user">
            <input type="hidden" name="token" value="$token">
            <button type="submit">Create New Game</button>
        </form>
    </div>
    <div class="box">
        <h3>Join Match</h3>
        <form action="/cgi-bin/tictactoe.cgi" method="POST">
            <input type="hidden" name="action" value="join">
            <input type="hidden" name="username" value="$user">
            <input type="hidden" name="token" value="$token">
            <input type="text" name="game_id" placeholder="Game ID (6 chars)" required maxlength="6">
            <button type="submit">Join Game</button>
        </form>
    </div>
    <form action="/cgi-bin/tictactoe.cgi" method="POST" style="width: 150px;">
        <input type="hidden" name="action" value="logout">
        <input type="hidden" name="username" value="$user">
        <input type="hidden" name="token" value="$token">
        <button type="submit">Logout</button>
    </form>
</body>
</html>
HTML
}

render_board() {
    local gid="$1"
    local user="$2"
    local token="$3"
    local state_resp
    state_resp=$(send_to_server "STATE $gid $user $token")

    if [[ "${state_resp%%|*}" != "OK" ]]; then
        render_message "ERR" "${state_resp#*|}"
        return
    fi

    IFS='|' read -r _ board status turn winner px po <<< "$state_resp"

    local my_mark="O"
    [[ "$user" == "$px" ]] && my_mark="X"

    local status_text=""
    local refresh=""
    local can_play=0

    if [[ "$status" == "WAITING" ]]; then
        status_text="Waiting for opponent... Share Game ID: <strong>$gid</strong>"
        refresh="<meta http-equiv=\"refresh\" content=\"2;url=/cgi-bin/tictactoe.cgi?action=view&game_id=$gid&username=$user&token=$token\">"
    elif [[ "$status" == "PLAYING" ]]; then
        if [[ "$turn" == "$my_mark" ]]; then
            status_text="Your turn (You are <strong>$my_mark</strong>)"
            can_play=1
        else
            status_text="Opponent's turn (You are <strong>$my_mark</strong>)..."
            refresh="<meta http-equiv=\"refresh\" content=\"2;url=/cgi-bin/tictactoe.cgi?action=view&game_id=$gid&username=$user&token=$token\">"
        fi
    elif [[ "$status" == "FINISHED" ]]; then
        if [[ "$winner" == "DRAW" ]]; then
            status_text="Match ended in a DRAW!"
        elif [[ "$winner" == "$my_mark" ]]; then
            status_text="YOU WON! ($winner)"
        else
            status_text="YOU LOST! Winner: $winner"
        fi
    elif [[ "$status" == "TIMEOUT" ]]; then
        status_text="Match closed due to inactivity (TIMEOUT)."
    fi

    render_header "$refresh"
    cat << HTML
    <p>$status_text</p>
    <form action="/cgi-bin/tictactoe.cgi" method="POST">
        <input type="hidden" name="action" value="move">
        <input type="hidden" name="game_id" value="$gid">
        <input type="hidden" name="username" value="$user">
        <input type="hidden" name="token" value="$token">
        <div class="board">
HTML

    for (( i=0; i<9; i++ )); do
        local c="${board:$i:1}"
        if [[ "$c" == "-" && "$can_play" -eq 1 ]]; then
            echo "<button type=\"submit\" name=\"cell\" value=\"$i\" class=\"cell\"></button>"
        else
            local display="$c"
            [[ "$c" == "-" ]] && display=""
            echo "<button type=\"button\" class=\"cell\" disabled>$display</button>"
        fi
    done

    cat << HTML
        </div>
    </form>
    <p>Game ID: <strong>$gid</strong> | $px (X) vs ${po:-...} (O)</p>
HTML

    if [[ "$status" == "FINISHED" || "$status" == "TIMEOUT" ]]; then
        cat << HTML
    <form action="/cgi-bin/tictactoe.cgi" method="POST" style="width: 200px;">
        <input type="hidden" name="action" value="lobby">
        <input type="hidden" name="username" value="$user">
        <input type="hidden" name="token" value="$token">
        <button type="submit">Back to Lobby</button>
    </form>
HTML
    fi

    echo "</body></html>"
}

render_message() {
    local status="$1"
    local msg="$2"
    render_header ""
    cat << HTML
    <div class="box">
        <h3>[$status]</h3>
        <p>$msg</p>
        <a href="/index.html">Back</a>
    </div>
</body>
</html>
HTML
}

case "$ACTION_IN" in
    register)
        RESP=$(send_to_server "REGISTER $USER_IN $PASS_IN")
        render_message "${RESP%%|*}" "${RESP#*|}"
        ;;
    login)
        RESP=$(send_to_server "LOGIN $USER_IN $PASS_IN")
        if [[ "${RESP%%|*}" == "OK" ]]; then
            render_lobby "$USER_IN" "${RESP#*|}"
        else
            render_message "ERR" "${RESP#*|}"
        fi
        ;;
    logout)
        send_to_server "LOGOUT $USER_IN $TOKEN_IN" > /dev/null
        render_message "OK" "Logged out safely."
        ;;
    lobby)
        render_lobby "$USER_IN" "$TOKEN_IN"
        ;;
    create)
        RESP=$(send_to_server "CREATE $USER_IN $TOKEN_IN")
        if [[ "${RESP%%|*}" == "OK" ]]; then
            render_board "${RESP#*|}" "$USER_IN" "$TOKEN_IN"
        else
            render_message "ERR" "${RESP#*|}"
        fi
        ;;
    join)
        RESP=$(send_to_server "JOIN $GAME_IN $USER_IN $TOKEN_IN")
        if [[ "${RESP%%|*}" == "OK" ]]; then
            render_board "${RESP#*|}" "$USER_IN" "$TOKEN_IN"
        else
            render_message "ERR" "${RESP#*|}"
        fi
        ;;
    move)
        send_to_server "MOVE $GAME_IN $USER_IN $TOKEN_IN $CELL_IN" > /dev/null
        render_board "$GAME_IN" "$USER_IN" "$TOKEN_IN"
        ;;
    view)
        render_board "$GAME_IN" "$USER_IN" "$TOKEN_IN"
        ;;
    *)
        render_message "ERR" "Invalid action"
        ;;
esac
