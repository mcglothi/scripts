#!/bin/bash
# launch-desktop.sh
# Master startup script for feynman desktop layout with validation

# 1. Wait for system/monitor stabilization
sleep 15

# Desktop IDs
WS1="1"
WS4="4"

validate_window() {
    local class="$1"
    local expected_x="$2"
    local expected_y="$3"
    
    local win_id=$(kdotool search --class "$class" | tail -n 1)
    if [ -z "$win_id" ]; then
        echo "VALIDATION FAILED: $class is not running."
        return 1
    fi
    
    local actual_x=$(qdbus org.kde.KWin /KWin org.kde.KWin.getWindowInfo "$win_id" | grep "^x:" | cut -d' ' -f2-)
    local actual_y=$(qdbus org.kde.KWin /KWin org.kde.KWin.getWindowInfo "$win_id" | grep "^y:" | cut -d' ' -f2-)
    
    if [ "$actual_x" -eq "$expected_x" ] && [ "$actual_y" -eq "$expected_y" ]; then
        echo "VALIDATION SUCCESS: $class at $actual_x,$actual_y"
        return 0
    else
        echo "VALIDATION WARNING: $class at $actual_x,$actual_y (Expected $expected_x,$expected_y)"
        return 1
    fi
}

launch_and_move() {
    local cmd="$1"
    local class="$2"
    local x="$3"
    local y="$4"
    local w="$5"
    local h="$6"
    local desktop="$7"
    local bin=$(echo "$cmd" | awk '{print $1}')

    if ! pgrep -x "$bin" > /dev/null; then
        [ "$bin" == "firefox" ] && export MOZ_ENABLE_WAYLAND=1
        $cmd &
        sleep 10
    fi

    local win_id=$(kdotool search --class "$class" | tail -n 1)
    if [ -n "$win_id" ]; then
        kdotool windowmove "$win_id" "$x" "$y"
        kdotool windowsize "$win_id" "$w" "$h"
        if [ "$desktop" == "all" ]; then
            kdotool set_desktop_for_window "$win_id" "all"
        elif [ -n "$desktop" ]; then
            kdotool set_desktop_for_window "$win_id" "$desktop"
        fi
        sleep 2
        validate_window "$class" "$x" "$y"
    fi
}

# Cleanup
for win in $(kdotool search --class "Brave-browser" | head -n -1); do kdotool windowclose "$win"; done
for win in $(kdotool search --class "firefox" | head -n -1); do kdotool windowclose "$win"; done
for win in $(kdotool search --class "konsole" | head -n -1); do kdotool windowclose "$win"; done

# Execution
launch_and_move "spotify" "spotify" 589 518 1280 874 "all"
launch_and_move "jellyfin-desktop" "org.jellyfin.JellyfinDesktop" 1869 518 1280 874 "all"
launch_and_move "signal-desktop" "signal" 589 1392 1280 768 "all"
launch_and_move "google-messages" "googlemessages-nativefier-11f104" 1869 1392 1280 768 "all"
launch_and_move "discord" "discord" 3149 1392 1280 768 "all"
launch_and_move "vacuumtube" "vacuumtube" 3149 518 1280 874 "all"
launch_and_move "firefox --new-instance" "firefox" 0 2160 1280 1440 "$WS1"
launch_and_move "konsole --workdir ~/code/AIKB" "konsole" 1281 2160 2559 1440 "$WS1"
launch_and_move "brave" "brave-browser" 3841 2160 1279 1440 "$WS1"
launch_and_move "steam" "steam" 2 2160 1634 1435 "$WS4"

echo "Desktop layout sequence complete."
