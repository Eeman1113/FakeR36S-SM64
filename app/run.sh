#!/bin/sh
# FakeR36S-OS entry point (the menu entry's COMMAND): the launcher works out of its own folder. The CPU runs at the
# max profile (turbo, pinned at the top clock) while the game is up, back to normal when it closes, as on Reader.
cd "$(dirname "$(readlink -f "$0")")" || exit 1
doas /usr/local/bin/cpuprofile max 2>/dev/null
sh ./sm64.sh "$@"
rc=$?
doas /usr/local/bin/cpuprofile normal 2>/dev/null
exit $rc
