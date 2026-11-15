#!/bin/bash

ENV_FILE="/home/mihai/tictactoe/.env"
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

HOST="${APP_HOST:-127.0.0.1}"
PORT="${APP_PORT:-9090}"
DATA_DIR="${DATA_DIR:-/home/mihai/tictactoe/data}"
SESSION_TTL="${SESSION_TTL:-60}"
GAME_TIMEOUT="${GAME_TIMEOUT:-60}"

USERS_DB="$DATA_DIR/users.db"
USERS_LOCK="$DATA_DIR/users.lock"
SESSIONS_DB="$DATA_DIR/sessions.db"
SESSIONS_LOCK="$DATA_DIR/sessions.lock"

mkdir -p "$DATA_DIR"
touch "$SESSIONS_DB"

if [[ ! -f "$USERS_DB" ]]; then
    users=()
    declare -p users > "$USERS_DB"
fi

verify_session() {
    local user="$1"
    local token="$2"
    [[ "$user" =~ ^[a-zA-Z0-9_]{3,16}$ ]] || return 1
    [[ "$token" =~ ^[a-f0-9]{16}$ ]] || return 1

    local now
    now=$(date +%s)

    (
        flock -x 201
        local line
        line=$(grep "^${user}|" "$SESSIONS_DB")
        [[ -z "$line" ]] && exit 1

        IFS='|' read -r _ stored_token last_seen <<< "$line"
        if [[ "$stored_token" == "$token" ]] && (( now - last_seen <= SESSION_TTL )); then
            grep -v "^${user}|" "$SESSIONS_DB" > "${SESSIONS_DB}.tmp"
            echo "${user}|${token}|${now}" >> "${SESSIONS_DB}.tmp"
            mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
            exit 0
        fi
        exit 1
    ) 201>"$SESSIONS_LOCK"
}

cleanup_worker() {
    while true; do
        sleep 5
        now=$(date +%s)

        for game_file in "$DATA_DIR"/game_*.db; do
            [[ -f "$game_file" ]] || continue
            base=$(basename "$game_file" .db)
            lock_file="$DATA_DIR/${base}.lock"

            (
                flock -x 200
                source "$game_file"
                if [[ "$STATUS" == "WAITING" || "$STATUS" == "PLAYING" ]]; then
                    if (( now - LAST_ACTIVITY > GAME_TIMEOUT )); then
                        STATUS="TIMEOUT"
                        TURN="-"
                        cat << GAME > "$game_file"
BOARD="$BOARD"
STATUS="$STATUS"
TURN="$TURN"
PLAYER_X="$PLAYER_X"
PLAYER_O="$PLAYER_O"
WINNER="$WINNER"
LAST_ACTIVITY="$LAST_ACTIVITY"
GAME
                    fi
                fi
            ) 200>"$lock_file"
        done

        (
            flock -x 201
            : > "${SESSIONS_DB}.clean"
            while IFS='|' read -r u t ts; do
                [[ -z "$u" ]] && continue
                if (( now - ts <= SESSION_TTL )); then
                    echo "${u}|${t}|${ts}" >> "${SESSIONS_DB}.clean"
                fi
            done < "$SESSIONS_DB"
            mv "${SESSIONS_DB}.clean" "$SESSIONS_DB"
        ) 201>"$SESSIONS_LOCK"
    done
}

check_winner() {
    local b="$1"
    local wins=("0 1 2" "3 4 5" "6 7 8" "0 3 6" "1 4 7" "2 5 8" "0 4 8" "2 4 6")
    for w in "${wins[@]}"; do
        read -r a c d <<< "$w"
        if [[ "${b:$a:1}" != "-" && "${b:$a:1}" == "${b:$c:1}" && "${b:$a:1}" == "${b:$d:1}" ]]; then
            echo "${b:$a:1}"
            return
        fi
    done
    if [[ "$b" != *"-"* ]]; then
        echo "DRAW"
        return
    fi
    echo "-"
}

save_game_state() {
    local file="$1"
    cat << GAME > "$file"
BOARD="$BOARD"
STATUS="$STATUS"
TURN="$TURN"
PLAYER_X="$PLAYER_X"
PLAYER_O="$PLAYER_O"
WINNER="$WINNER"
LAST_ACTIVITY="$LAST_ACTIVITY"
GAME
}

handle_client() {
    read -r cmd arg1 arg2 arg3 arg4

    case "$cmd" in
        REGISTER)
            if [[ ! "$arg1" =~ ^[a-zA-Z0-9_]{3,16}$ ]] || [[ ! "$arg2" =~ ^[a-zA-Z0-9_@#!-]{1,32}$ ]]; then
                echo "ERR|Invalid username or password format"
                return
            fi
            (
                flock -x 200
                source "$USERS_DB"
                for (( i=0; i<${#users[@]}; i+=2 )); do
                    if [[ "${users[$i]}" == "$arg1" ]]; then
                        echo "ERR|Username already exists"
                        exit 0
                    fi
                done
                users+=("$arg1" "$arg2")
                declare -p users > "$USERS_DB"
                echo "OK|Account created for $arg1"
            ) 200>"$USERS_LOCK"
            ;;

        LOGIN)
            if [[ ! "$arg1" =~ ^[a-zA-Z0-9_]{3,16}$ ]] || [[ ! "$arg2" =~ ^[a-zA-Z0-9_@#!-]{1,32}$ ]]; then
                echo "ERR|Invalid username or password format"
                return
            fi

            valid_creds=0
            (
                flock -s 200
                source "$USERS_DB"
                for (( i=0; i<${#users[@]}; i+=2 )); do
                    if [[ "${users[$i]}" == "$arg1" && "${users[$((i+1))]}" == "$arg2" ]]; then
                        exit 0
                    fi
                done
                exit 1
            ) 200>"$USERS_LOCK" && valid_creds=1

            if [[ "$valid_creds" -eq 0 ]]; then
                echo "ERR|Invalid username or password"
                return
            fi

            now=$(date +%s)
            (
                flock -x 201
                existing=$(grep "^${arg1}|" "$SESSIONS_DB")
                if [[ -n "$existing" ]]; then
                    IFS='|' read -r _ _ last_seen <<< "$existing"
                    if (( now - last_seen <= SESSION_TTL )); then
                        echo "ERR|Account is already logged in on another session"
                        exit 0
                    fi
                fi

                token=$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')
                grep -v "^${arg1}|" "$SESSIONS_DB" > "${SESSIONS_DB}.tmp"
                echo "${arg1}|${token}|${now}" >> "${SESSIONS_DB}.tmp"
                mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
                echo "OK|$token"
            ) 201>"$SESSIONS_LOCK"
            ;;

        LOGOUT)
            if verify_session "$arg1" "$arg2"; then
                (
                    flock -x 201
                    grep -v "^${arg1}|" "$SESSIONS_DB" > "${SESSIONS_DB}.tmp"
                    mv "${SESSIONS_DB}.tmp" "$SESSIONS_DB"
                ) 201>"$SESSIONS_LOCK"
            fi
            echo "OK|Logged out"
            ;;

        CREATE)
            verify_session "$arg1" "$arg2" || { echo "ERR|Session expired or invalid"; return; }

            game_id=$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')
            BOARD="---------"
            STATUS="WAITING"
            TURN="X"
            PLAYER_X="$arg1"
            PLAYER_O=""
            WINNER="-"
            LAST_ACTIVITY=$(date +%s)
            save_game_state "$DATA_DIR/game_${game_id}.db"
            echo "OK|$game_id"
            ;;

        JOIN)
            verify_session "$arg2" "$arg3" || { echo "ERR|Session expired or invalid"; return; }
            [[ "$arg1" =~ ^[a-f0-9]{6}$ ]] || { echo "ERR|Invalid game ID"; return; }

            game_file="$DATA_DIR/game_${arg1}.db"
            [[ -f "$game_file" ]] || { echo "ERR|Game not found"; return; }
            (
                flock -x 200
                source "$game_file"
                [[ "$STATUS" == "WAITING" ]] || { echo "ERR|Game is full or finished"; exit 0; }
                [[ "$PLAYER_X" != "$arg2" ]] || { echo "ERR|Cannot join your own game"; exit 0; }
                PLAYER_O="$arg2"
                STATUS="PLAYING"
                LAST_ACTIVITY=$(date +%s)
                save_game_state "$game_file"
                echo "OK|$arg1"
            ) 200>"$DATA_DIR/game_${arg1}.lock"
            ;;

        MOVE)
            verify_session "$arg2" "$arg3" || { echo "ERR|Session expired or invalid"; return; }
            if [[ ! "$arg1" =~ ^[a-f0-9]{6}$ ]] || [[ ! "$arg4" =~ ^[0-8]$ ]]; then
                echo "ERR|Invalid move parameters"
                return
            fi
            game_file="$DATA_DIR/game_${arg1}.db"
            [[ -f "$game_file" ]] || { echo "ERR|Game not found"; return; }
            (
                flock -x 200
                source "$game_file"
                [[ "$STATUS" == "PLAYING" ]] || { echo "ERR|Game is not active"; exit 0; }

                mark=""
                if [[ "$arg2" == "$PLAYER_X" && "$TURN" == "X" ]]; then
                    mark="X"
                elif [[ "$arg2" == "$PLAYER_O" && "$TURN" == "O" ]]; then
                    mark="O"
                else
                    echo "ERR|Not your turn"
                    exit 0
                fi

                if [[ "${BOARD:$arg4:1}" != "-" ]]; then
                    echo "ERR|Cell already occupied"
                    exit 0
                fi

                BOARD="${BOARD:0:$arg4}${mark}${BOARD:$((arg4+1))}"
                LAST_ACTIVITY=$(date +%s)

                WINNER=$(check_winner "$BOARD")
                if [[ "$WINNER" != "-" ]]; then
                    STATUS="FINISHED"
                    TURN="-"
                else
                    [[ "$TURN" == "X" ]] && TURN="O" || TURN="X"
                fi

                save_game_state "$game_file"
                echo "OK|MOVED"
            ) 200>"$DATA_DIR/game_${arg1}.lock"
            ;;

        STATE)
            verify_session "$arg2" "$arg3" || { echo "ERR|Session expired or invalid"; return; }
            [[ "$arg1" =~ ^[a-f0-9]{6}$ ]] || { echo "ERR|Invalid game ID"; return; }

            game_file="$DATA_DIR/game_${arg1}.db"
            [[ -f "$game_file" ]] || { echo "ERR|Game not found"; return; }
            (
                flock -s 200
                source "$game_file"
                echo "OK|$BOARD|$STATUS|$TURN|$WINNER|$PLAYER_X|$PLAYER_O"
            ) 200>"$DATA_DIR/game_${arg1}.lock"
            ;;

        *)
            echo "ERR|Unknown command"
            ;;
    esac
}

export -f handle_client verify_session check_winner save_game_state
export DATA_DIR USERS_DB USERS_LOCK SESSIONS_DB SESSIONS_LOCK SESSION_TTL GAME_TIMEOUT

cleanup_worker &
CLEANUP_PID=$!
trap "kill $CLEANUP_PID 2>/dev/null; exit" SIGINT SIGTERM

echo "Server listening on $HOST:$PORT (Cleanup PID: $CLEANUP_PID)..."
socat TCP-LISTEN:"$PORT",bind="$HOST",reuseaddr,fork EXEC:"bash -c handle_client"
