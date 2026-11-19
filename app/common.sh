# common.sh: the launcher's work, sourced in the port's folder once sm64.sh sets PORT, ELF, TITLE, O2R (the archive
# a ROM makes), CONFIG (the game's settings file) and TAKES (the ROMs it takes, in a few words). From
# FakeR36S-Ocarina's app/common.sh.
# The game makes its assets from the player's ROM by itself, in its ROM Extraction window, when it is started with
# the ROM: this finds the ROM (in HOME first, by the name in its header, in any byte order, loose or zipped). Saves,
# settings, save states and assets live in HOME/.config/<port>, outside the port: a new install needs no ROM.
app=$(pwd)
data=$HOME/.config/$PORT
log=$HOME/logs/$PORT.log
export SHIP_HOME=$data
export LD_LIBRARY_PATH=$app/libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export SDL_VIDEODRIVER=${SDL_VIDEODRIVER:-kmsdrm}
. /etc/profile.d/sdl_controller.sh 2>/dev/null
mkdir -p "$data" "$HOME/logs"

# the SHA-1s Ghostship takes (src/port/GameExtractor.cpp), of the .z64 (big-endian) file
SHA_US=9bef1128717f958171a4afac3ed78ee2bb4e86ce
SHA_JP=8a20a5c83d6ceb0f0506cfc9fa20d8f438cafe51

# the setup screen with one error and its prompt, then back to the menu
fail() {
    _fmt=$1
    shift
    {
        printf 'T %s\n' "$TITLE"
        printf 'U %s\n' "Getting your game ready"
        printf 'E %s\n' "$(printf "$_fmt" "$@")"
        printf 'W %s\n' "Press any button to go back"
    } | tee -a "$log" | "$app/setup" "$app/fonts/PixelifySans.ttf" > /dev/null
    exit 1
}

ready() {
    [ -f "$data/$O2R" ] || [ -f "$app/$O2R" ]
}

# The first 64 bytes on stdin, in .z64 order, as hex: the byte order from the first word (z64 big-endian, v64
# byte-swapped, n64 little-endian). "z64", "v64" or "n64" on the first line, the hex on the second.
rom_header() {
    _h=$(head -c 64 | od -An -tx1 | tr -d ' \n')
    case $(echo "$_h" | cut -c1-8) in
        80371240) echo z64; echo "$_h" ;;
        37804012) echo v64; echo "$_h" | sed 's/\(..\)\(..\)/\2\1/g' ;;
        40123780) echo n64; echo "$_h" | sed 's/\(..\)\(..\)\(..\)\(..\)/\4\3\2\1/g' ;;
        *) return 1 ;;
    esac
}

# Super Mario 64 by the name at 0x20 ("SUPER MARIO 64"): on stdin, the ROM's start; prints its byte order
is_sm64() {
    _r=$(rom_header) || return 1
    _o=$(echo "$_r" | head -n 1)
    echo "$_r" | tail -n 1 | cut -c65-92 | grep -qi '^5355504552204d4152494f203634$' || return 1
    echo "$_o"
}

# The first Super Mario 64 ROM, as "<byte order>|<file>|<entry in the zip, or nothing>": loose ROMs in HOME, the
# port's folder and the usual N64 folders first, then anywhere but the hidden folders (to a depth of 5), then zips
# in HOME itself and in any n64 folder. Names with spaces and brackets are fine ("Super Mario 64 (USA).z64").
find_rom() {
    for _f in "$HOME"/*.[zZnNvV]64 "$app"/*.[zZnNvV]64 "$HOME"/roms/n64/*.[zZnNvV]64 "$HOME"/n64/*.[zZnNvV]64; do
        [ -f "$_f" ] || continue
        _o=$(is_sm64 < "$_f") && { echo "$_o|$_f|"; return 0; }
    done
    _r=$(find "$HOME" -maxdepth 5 \( -path "$HOME/.*" -o -path "$HOME/apps" \) -prune -o -type f \( -iname '*.z64' -o \
            -iname '*.n64' -o -iname '*.v64' \) -print 2>/dev/null |
        while IFS= read -r _f; do
            _o=$(is_sm64 < "$_f") && { echo "$_o|$_f|"; break; }
        done)
    [ -z "$_r" ] || { echo "$_r"; return 0; }
    for _z in "$HOME"/*.zip "$HOME"/*.ZIP "$app"/*.zip "$HOME"/*/n64/*.zip "$HOME"/*/N64/*.zip "$HOME"/n64/*.zip; do
        [ -f "$_z" ] || continue
        _r=$(unzip -l "$_z" 2>/dev/null | awk '{ $1 = $2 = $3 = ""; sub(/^ +/, ""); print }' |
            grep -i -E '\.(z64|n64|v64)$' | while IFS= read -r _e; do
                _o=$(unzip -p "$_z" "$_e" 2>/dev/null | is_sm64) && { echo "$_o|$_z|$_e"; break; }
            done)
        [ -z "$_r" ] || { echo "$_r"; return 0; }
    done
    return 1
}

# What an exit status means, for the log
exit_reason() {
    case $1 in
        0) echo "clean exit" ;;
        1) echo "error exit" ;;
        3) echo "the ROM extraction failed (see the [FakeR36S] lines above)" ;;
        127) echo "the game could not be started (missing file or library)" ;;
        130) echo "killed by SIGINT" ;;
        132) echo "SIGILL: illegal instruction (an ARMv8 instruction on the ARMv7 A23?)" ;;
        134) echo "SIGABRT: abort" ;;
        135) echo "SIGBUS: bus error" ;;
        136) echo "SIGFPE: arithmetic error" ;;
        137) echo "SIGKILL: killed (out of memory, or fr-padwatch 5 s after Select+Start)" ;;
        139) echo "SIGSEGV: crash (invalid memory access)" ;;
        143) echo "SIGTERM" ;;
        *) [ "$1" -gt 128 ] 2>/dev/null && echo "killed by signal $(($1 - 128))" || echo "exit status $1" ;;
    esac
}

# The game, its output in the log; arguments go to it (a ROM to extract). Select+Start closes it (fr-padwatch, and
# the game's own hotkey); the game writes its autosave state on the way out. Not during the first start's
# extraction: fr-padwatch would kill it 5 s after Select+Start, losing sm64.o2r (the game holds a quit until the
# extraction is done, and says so on screen).
play() {
    [ -f "$data/$CONFIG" ] || cp "$app/defaults.json" "$data/$CONFIG"
    [ -f "$data/env" ] && { set -a; . "$data/env"; set +a; }
    # the previous run's log is kept as sm64.prev.log, so a crash's evidence survives one relaunch
    [ -f "$log" ] && mv -f "$log" "${log%.log}.prev.log"
    _watch=
    [ $# -eq 0 ] && [ -x /usr/bin/fr-padwatch ] && _watch=/usr/bin/fr-padwatch
    {
        echo "=== $PORT start $(date)${1:+, extracting $1}"
        grep -E "MemTotal|MemAvailable|SwapFree" /proc/meminfo
        df -k "$HOME" 2>/dev/null | tail -n 1
        cd "$app" && $_watch "./$ELF" "$@"
        _rc=$?
        echo "=== exit $_rc: $(exit_reason $_rc)"
        grep -E "MemAvailable|SwapFree" /proc/meminfo
        ls -l "$data/$O2R" 2>/dev/null || echo "no $data/$O2R"
        echo "$_rc" > "$data/.last-exit"
    } >> "$log" 2>&1
    sync
    return "$(cat "$data/.last-exit" 2>/dev/null || echo 1)"
}

start() {
    # a zipped ROM unpacked for an extraction: closing the game from its menu ends this script with it
    rm -f "$data"/rom.z64
    ready && { play; return; }

    _found=$(find_rom) || fail "No %s ROM found. Copy yours to HOME (a .z64, .n64 or .v64 file, or a zip of one) and open the game again. It takes %s." "$TITLE" "$TAKES"
    _order=${_found%%|*}
    _rest=${_found#*|}
    _file=${_rest%%|*}
    _entry=${_rest#*|}
    _rom=$_file
    if [ -n "$_entry" ]; then
        _rom=$data/rom.z64
        unzip -p "$_file" "$_entry" > "$_rom" || { rm -f "$_rom"; fail "The ROM in %s could not be unpacked: is the zip whole?" "${_file##*/}"; }
    fi
    # Ghostship takes two versions; a .z64 is checked here, so a wrong one gets a clear message instead of a stuck
    # prompt (the game converts .v64 and .n64 and checks those itself)
    if [ "$_order" = z64 ] && command -v sha1sum > /dev/null; then
        _sha=$(sha1sum "$_rom" | cut -d ' ' -f 1)
        case $_sha in
            $SHA_US | $SHA_JP) ;;
            *) rm -f "$data"/rom.z64
               fail "%s is Super Mario 64, but not a version Ghostship takes (%s). Its SHA-1 is %s." "${_file##*/}" "$TAKES" "$_sha" ;;
        esac
    fi
    echo "$(date '+%F %T') extracting $_file${_entry:+ ($_entry)} ($_order)" >> "$HOME/logs/$PORT-import.log"
    play "$_rom"
    _rc=$?
    rm -f "$data"/rom.z64
    echo "$(date '+%F %T') exit $_rc: $(exit_reason $_rc); $(ls -l "$data/$O2R" 2>/dev/null || echo "no $O2R")" \
        >> "$HOME/logs/$PORT-import.log"
    ready || fail "The game's files could not be made from your ROM ($(exit_reason $_rc)). HOME/logs/sm64.log says why; open the game again to retry."
}
