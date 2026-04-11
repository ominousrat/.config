#!/usr/bin/env bash

if [[ -z "$ROFI_RETV" || "$ROFI_RETV" == "0" ]]; then
    echo "   /term"
    echo " 󰖟  /browser"
    echo "   /config"
    exit 0
fi

case "$1" in
    "/term"*)
        kitty
        ;;
    "/browser"*)
        brave
        ;;
    "/config"*)
        code ~/.config
        ;;
esac