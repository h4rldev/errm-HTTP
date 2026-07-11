#!/usr/bin/env bash

if [ -n "$REBAR_PROFILE" ]; then
    echo "$REBAR_PROFILE"
    exit 0
fi

CURRENT_PID=$$
while [ "$CURRENT_PID" != "1" ]; do
    CMD=$(ps -o args= -p $CURRENT_PID 2>/dev/null)
    if [[ "$CMD" =~ as[[:space:]]+([a-zA-Z0-9_-]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        exit 0
    fi
    CURRENT_PID=$(ps -o ppid= -p $CURRENT_PID 2>/dev/null | tr -d ' ')
done

echo "debug"
