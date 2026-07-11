#!/usr/bin/env bash

if [ -n "$REBAR_PROFILE" ]; then
    PROFILE="$REBAR_PROFILE"
else
    PROFILE="$(./scripts/detect_profile.sh)"
fi

exec just build_nifs "$PROFILE"
