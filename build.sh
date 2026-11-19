#!/usr/bin/env bash
# Super Mario 64 (HarbourMasters' Ghostship) for FakeR36S-OS, without the game. From FakeR36S-Ocarina's build.sh.
#   ./build.sh game        the armhf binary, with the GLES2 renderer (patches/lus) and the FakeR36S patches
#   ./build.sh port        ghostship.o2r, the port's own archive (fonts, shaders, textures; nothing of the game)
#   ./build.sh shaders     every GLES2 shader variant through glslang (GLSL ES 1.00), see tools/shadercheck.cpp
#   ./build.sh libs        the libraries it needs that FakeR36S-OS lacks, into libs/
#   ./build.sh check       ARMv8-only instructions in the binary and libs/ (there must be none), and NEEDED
#   ./build.sh fakers36s   out/FakeR36S-SM64-<version>.zip: ports/sm64 and its menu entry, unzipped into HOME.
#                          No game in it: the player's ROM is extracted on the console, by the game. APP_VERSION:
#                          default git describe
#   ./build.sh smoke [s]   the packaged port under qemu-arm on Xvfb (Mesa llvmpipe, GLES2), with no ROM: it must start,
#                          make its GLES2 context and draw its first-start window; screenshots in out/smoke
#   ./build.sh lima        the same GLES2 shader variants through lima's own compiler (the Mali-400 driver, faked by
#                          Mesa's drm-shim): what the console will compile, without the console
#   ./build.sh             game, port, libs, check, fakers36s
# Output in out/sm64. Runs in the fakers36s-sm64 image (Dockerfile), sources and build trees in the sm64-work volume.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=fakers36s-sm64

if [ ! -f /.dockerenv ]; then
    docker image inspect $IMAGE >/dev/null 2>&1 || docker build -t $IMAGE "$HERE"
    case " $* " in *" lima "*)
        docker image inspect $IMAGE-lima >/dev/null 2>&1 || docker build -t $IMAGE-lima -f "$HERE/tools/lima.Dockerfile" "$HERE/tools"
        IMAGE=$IMAGE-lima ;;
    esac
    case " $* " in *" smoke "*)
        docker image inspect $IMAGE-smoke >/dev/null 2>&1 || docker build -t $IMAGE-smoke -f "$HERE/tools/smoke.Dockerfile" "$HERE/tools"
        IMAGE=$IMAGE-smoke ;;
    esac
    exec docker run --rm -i -v "$HERE:/repo" -v sm64-work:/work -e GL_JOBS -e APP_VERSION $IMAGE /repo/build.sh "$@"
fi

PORT=sm64
URL=https://github.com/HarbourMasters/Ghostship.git TAG=3.0.0 REV=deb091c2
W=/work/sm64
SRC=$W/src/Ghostship BLD=$W/build
OUT=/repo/out/$PORT
ARMFLAGS="-march=armv7-a -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard"
JOBS=${GL_JOBS:-$(nproc)}
PREFIX=$BLD/armhf-prefix
LIBZIP=1.12.1
LIBZIP_SHA=3b66fe92cbc768d8d4d16e1427bfb7399e15d9c2795c2fc482e7b30a6332a422
ELF=Ghostship

source_tree() {
    mkdir -p "$W/src" "$BLD" "$OUT"
    [ -d "$SRC" ] || git clone -q --depth 1 --branch $TAG "$URL" "$SRC"
    [ "$(git -C "$SRC" rev-parse --short=8 HEAD)" = $REV ] || { echo "Ghostship is not at $REV" >&2; exit 1; }
    git -C "$SRC" submodule update --init --depth 1 -q
    apply_patches "$SRC" "$HERE"/patches/ghostship/*.patch
    apply_patches "$SRC/libultraship" "$HERE"/patches/lus/*.patch
}

# Patches $2... onto the tree $1; when one changed since it was applied, start again from a clean tree
apply_patches() {
    local tree=$1 p; shift
    for p in "$@"; do
        git -C "$tree" apply --reverse --check "$p" 2>/dev/null && continue
        git -C "$tree" apply --check "$p" 2>/dev/null || {
            git -C "$tree" checkout -q -- .
            git -C "$tree" clean -q -fd
            git -C "$tree" apply --check "$p" || { echo "patch $p does not apply" >&2; exit 1; }
            apply_patches "$tree" "$@"
            return
        }
        git -C "$tree" apply "$p"
    done
}

toolchain() {
    cat > "$BLD/armhf.cmake" <<'EOF'
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR arm)
set(CMAKE_C_COMPILER arm-linux-gnueabihf-gcc)
set(CMAKE_CXX_COMPILER arm-linux-gnueabihf-g++)
set(CMAKE_LIBRARY_ARCHITECTURE arm-linux-gnueabihf)
set(ENV{PKG_CONFIG_LIBDIR} /usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/share/pkgconfig)
EOF
}

# libultraship wants a system libzip; the console has none, and Debian's pulls in GnuTLS. Static, zlib only.
build_libzip() {
    local t=$W/src/libzip-$LIBZIP.tar.gz
    [ -f "$PREFIX/lib/libzip.a" ] && return
    echo "$LIBZIP_SHA  $t" | sha256sum -c --status 2>/dev/null ||
        curl -fsSL -o "$t" https://github.com/nih-at/libzip/releases/download/v$LIBZIP/libzip-$LIBZIP.tar.gz
    echo "$LIBZIP_SHA  $t" | sha256sum -c --quiet
    rm -rf "$BLD/libzip-src"; mkdir -p "$BLD/libzip-src"
    tar -xzf "$t" -C "$BLD/libzip-src" --strip-components=1
    cmake -S "$BLD/libzip-src" -B "$BLD/libzip" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS" -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF -DENABLE_COMMONCRYPTO=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF \
        -DENABLE_OPENSSL=OFF -DENABLE_WINDOWS_CRYPTO=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF \
        -DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF
    cmake --build "$BLD/libzip" -j "$JOBS" --target install
}

# Scripting (TinyCC mods) and the Satella network client are off: neither builds for armhf nor matters offline.
# -no-pie and patches/ghostship/0005's linker script: the game's code and data at the same address on every run,
# with the game's own variables gathered in one range (save states on the card).
game() {
    toolchain
    build_libzip
    cmake -S "$SRC" -B "$BLD/armhf" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$BLD/armhf.cmake" -DCMAKE_PREFIX_PATH="$PREFIX" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="$ARMFLAGS -isystem $PREFIX/include" \
        -DCMAKE_CXX_FLAGS="$ARMFLAGS -isystem $PREFIX/include" \
        -DCMAKE_PROJECT_Ghostship_INCLUDE="$HERE/cmake/ghostship-deps.cmake" \
        -DUSE_OPENGLES=ON -DUSE_GLES2=ON -DENABLE_SCRIPTING=OFF -DUSE_SATELLA=OFF -DUSE_NETWORKING=OFF -DFAKER36S=ON \
        -DCMAKE_EXE_LINKER_FLAGS=-no-pie
    cmake --build "$BLD/armhf" -j "$JOBS" --target $ELF -- -k 0
    cp "$BLD/armhf/$ELF" "$OUT/"
    arm-linux-gnueabihf-strip "$OUT/$ELF"
    ls -l "$OUT/$ELF"
}

# Torch for this machine, standalone: it packs the port's folder (with the patched shaders) into ghostship.o2r
torch_native() {
    [ -x "$BLD/torch-native/torch" ] && return
    cmake -S "$SRC/Torch" -B "$BLD/torch-native" -G Ninja -DCMAKE_BUILD_TYPE=Release -DUSE_STANDALONE=ON \
        -DBUILD_MK64=OFF -DBUILD_SF64=OFF -DBUILD_FZERO=OFF -DBUILD_MARIO_ARTIST=OFF
    cmake --build "$BLD/torch-native" -j "$JOBS" --target torch
}

port_o2r() {
    torch_native
    local v
    v=$(sed -n 's/^project(Ghostship VERSION \([0-9.]*\).*/\1/p' "$SRC/CMakeLists.txt")
    rm -rf "$SRC/port/shaders"
    cp -r "$SRC/libultraship/src/fast/shaders" "$SRC/port/shaders"
    (cd "$SRC" && rm -f ghostship.o2r && "$BLD/torch-native/torch" pack port ghostship.o2r o2r -u "$v")
    cp "$SRC/ghostship.o2r" "$OUT/"
    ls -l "$OUT/ghostship.o2r"
}

# Every combination of the shader's switches that matters, rendered by prism and compiled by glslang as GLSL ES 1.00
# (each vertex and fragment shader linked as one program)
shaders() {
    local d=$BLD/armhf/_deps
    [ -d "$d/prism-src" ] || { echo "no $d/prism-src: ./build.sh game first"; exit 1; }
    cmake -S "$HERE/tools/shadercheck" -B "$BLD/shadercheck" -G Ninja -DCMAKE_BUILD_TYPE=Release \
        -DPRISM_DIR="$d/prism-src" -DSPDLOG_DIR="$d/spdlog-src"
    cmake --build "$BLD/shadercheck" -j "$JOBS"
    rm -rf "$BLD/shaders"; mkdir -p "$BLD/shaders"
    "$BLD/shadercheck/shadercheck" "$SRC/libultraship/src/fast/shaders/opengl/gles2.shader.glsl" "$BLD/shaders"
    local f bad=0 n=0
    for f in "$BLD"/shaders/*.vert; do
        n=$((n + 1))
        glslangValidator -l "$f" "${f%.vert}.frag" > "${f%.vert}.log" 2>&1 || {
            bad=$((bad + 1))
            if [ $bad -le 3 ]; then
                echo "== ${f%.vert}"; cat "${f%.vert}.log"
                echo "-- vertex:"; grep -n . "$f"; echo "-- fragment:"; grep -n . "${f%.vert}.frag"
            fi
        }
    done
    echo "== $n shader programs, $bad failed"
    [ $bad = 0 ]
}

# The shader variants of `shaders` compiled, linked and drawn by Mesa's lima driver under its drm-shim (tools/
# lima.Dockerfile): lima's vertex compiler takes no loops, no indirect uniforms and 304 vec4 of uniforms and temps
lima() {
    local m=/opt/mesa lib d=$BLD/lima n
    lib=$(dirname "$(find $m -name 'libEGL.so' | head -1)")
    cmake -S "$HERE/tools/shadercheck" -B "$BLD/shadercheck-lima" -G Ninja -DCMAKE_BUILD_TYPE=Release
    cmake --build "$BLD/shadercheck-lima" -j "$JOBS"
    rm -rf "$d"; mkdir -p "$d"
    "$BLD/shadercheck-lima/shadercheck" "$SRC/libultraship/src/fast/shaders/opengl/gles2.shader.glsl" "$d"
    n=$(ls "$d"/*.vert | wc -l)
    [ "$n" -le "${LIMA_PROGRAMS:-600}" ] || n=${LIMA_PROGRAMS:-600}
    gcc -O1 -Wall -I$m/include "$HERE/tools/limacheck/limacheck.c" -L"$lib" -Wl,-rpath,"$lib" -lEGL -lGLESv2 -lgbm \
        -o "$BLD/limacheck"
    mkdir -p /repo/out/lima
    # lima's own messages go to stderr, interleaved with the "== NNNN" markers; a time limit in case one hangs
    LD_LIBRARY_PATH=$lib:$(dirname "$(find $m -name 'libgallium*.so' | head -1)") \
    LD_PRELOAD=$m/liblima_noop_drm_shim.so LIMA_DEBUG=shaderdb,precompile LIBGL_DRIVERS_PATH=$lib/dri \
        GBM_BACKENDS_PATH=$lib/gbm timeout 2400 stdbuf -oL -eL "$BLD/limacheck" "$d" "$n" > "$d/lima.log" 2>&1 &
    local pid=$!
    while kill -0 $pid 2>/dev/null; do
        sleep 60
        echo "lima: $(grep -c '^== [0-9]' "$d/lima.log") of $n programs, $(grep -c 'SHADER-DB' "$d/lima.log") shaders compiled"
        cp "$d/lima.log" /repo/out/lima/
    done
    wait $pid || echo "limacheck ended with $?"
    cp "$d/lima.log" /repo/out/lima/
    python3 - "$d" <<'PY'
import re, sys, os
d = sys.argv[1]
log = open(os.path.join(d, "lima.log"), errors="replace").read().splitlines()
print("\n".join(log[:3]))
sections, cur = {}, None
for line in log:
    m = re.match(r"== (\d{4})$", line)
    if m:
        cur = m.group(1)
        sections.setdefault(cur, [])
        continue
    if cur is not None:
        sections[cur].append(line)
bad = []
stats = 0
for k, lines in sections.items():
    text = "\n".join(lines)
    n = len(re.findall(r"SHADER-DB: MESA_SHADER_(VERTEX|FRAGMENT) shader:", text))
    stats += n
    # both shaders must have compiled (a stats line each) and lima must not have complained
    if n < 2 or re.search(r"FAIL|gpir:|ppir:|lima:.*(fail|error|unsupported)|not implemented|unsupported", text, re.I):
        bad.append((k, text))
insts = [int(x) for x in re.findall(r"MESA_SHADER_VERTEX shader: (\d+) inst", "\n".join(log))]
finsts = [int(x) for x in re.findall(r"MESA_SHADER_FRAGMENT shader: (\d+) inst", "\n".join(log))]
print(f"== lima: {len(sections)} programs, {stats} shaders compiled, {len(bad)} with errors")
if insts and finsts:
    print(f"== vertex instructions: max {max(insts)}, mean {sum(insts) // len(insts)}; "
          f"fragment: max {max(finsts)}, mean {sum(finsts) // len(finsts)}")
for k, text in bad[:4]:
    print(f"---- {k}:\n{text[:3000]}")
    for ext in ("vert", "frag"):
        print(f"-- {k}.{ext}:")
        for i, l in enumerate(open(os.path.join(d, f"{k}.{ext}")).read().splitlines(), 1):
            if l.strip():
                print(f"{i:4}: {l}")
if not sections:
    print("\n".join(log[-40:]))
sys.exit(1 if bad or not sections else 0)
PY
}

# What FakeR36S-OS has (glibc, the C++ runtime, SDL2 and SDL2_ttf, Mesa, ALSA, zlib, libpng, freetype, OpenAL)
SYSTEM_LIBS=" ld-linux-armhf.so.3 libc.so.6 libm.so.6 libdl.so.2 libpthread.so.0 librt.so.1 libstdc++.so.6 libgcc_s.so.1
    libSDL2-2.0.so.0 libSDL2_ttf-2.0.so.0 libz.so.1 libpng16.so.16 libasound.so.2 libdrm.so.2 libEGL.so.1
    libGLESv2.so.2 libfreetype.so.6 libopenal.so.1 "

# Copy each NEEDED library (and its own NEEDED, recursively) that FakeR36S-OS doesn't ship
libs() {
    local queue=("$OUT/$ELF") seen=" " f lib path
    rm -rf "$OUT/libs"; mkdir -p "$OUT/libs"
    while [ ${#queue[@]} -gt 0 ]; do
        f=${queue[0]}; queue=("${queue[@]:1}")
        for lib in $(arm-linux-gnueabihf-readelf -d "$f" | sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
            case "$seen" in *" $lib "*) continue ;; esac
            seen="$seen$lib "
            case "$(echo $SYSTEM_LIBS | sed 's/^/ /; s/$/ /')" in *" $lib "*) continue ;; esac
            path=$(find /usr/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf -name "$lib" 2>/dev/null | head -1)
            [ -n "$path" ] || { echo "missing on both sides: $lib" >&2; continue; }
            cp -L "$path" "$OUT/libs/"
            queue+=("$path")
        done
    done
    ls -l "$OUT/libs"
}

# The A23 is a real ARMv7 (Cortex-A7): one ARMv8-only instruction is a SIGILL. None may be in what we ship. The
# game is disassembled before stripping, so its mapping symbols tell code ($a, $t) from data ($d); the bundled
# libraries and the setup screen are stripped, so for them the build attributes count, with a disassembly in Thumb
# mode (Debian's armhf default) for information.
V8='\s(vrint[anpmzxr]|vsel(eq|ge|gt|vs)|vmaxnm|vminnm|vcvt[anpm]\.|lda(r|ex|exd)?[bh]?\s|stl(r|ex|exd)?[bh]?\s|aes[edm]|aesimc|sha1[cmhps]|sha256|vmull\.p64|crc32|sevl|dmb\s+(ish|osh|nsh)?ld)'
check() {
    local f n bad=0 arch
    n=$(arm-linux-gnueabihf-objdump -d "$BLD/armhf/$ELF" | grep -c -E "$V8" || true)
    echo "$ELF: $n ARMv8-only instructions"
    [ "$n" = 0 ] || { bad=1; arm-linux-gnueabihf-objdump -d "$BLD/armhf/$ELF" | grep -E "$V8" | head -20; }
    for f in "$OUT"/libs/* "$OUT/setup"; do
        [ -f "$f" ] || continue
        arch=$(arm-linux-gnueabihf-readelf -A "$f" | sed -n 's/.*Tag_CPU_arch: //p')
        n=$(arm-linux-gnueabihf-objdump -d -M force-thumb "$f" | grep -c -E "$V8" || true)
        echo "$(basename "$f"): Tag_CPU_arch $arch, $n ARMv8-looking words in a Thumb disassembly"
        case "$arch" in v8* | "") bad=1 ;; esac
    done
    echo "== NEEDED by $ELF:"
    arm-linux-gnueabihf-readelf -d "$OUT/$ELF" | sed -n 's/.*Shared library: \[\(.*\)\]/  \1/p'
    echo "== attributes:"
    arm-linux-gnueabihf-readelf -A "$OUT/$ELF" | grep -E 'Tag_CPU_arch|Tag_FP_arch|Tag_Advanced_SIMD|Tag_ABI_VFP_args'
    echo "== the game's variables for save states (fakers36s-state.ld):"
    arm-linux-gnueabihf-readelf -SW "$BLD/armhf/$ELF" | grep -E '\.fr_state|\s\.data\s|\s\.bss\s' || true
    arm-linux-gnueabihf-readelf -SW "$BLD/armhf/$ELF" | grep -q '\.fr_state_bss' || { echo "no .fr_state_bss"; bad=1; }
    echo "== highest GLIBC symbol version: $(arm-linux-gnueabihf-objdump -T "$OUT/$ELF" | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1)"
    echo "== highest GLIBCXX: $(arm-linux-gnueabihf-objdump -T "$OUT/$ELF" | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -1)"
    [ $bad = 0 ]
}

# FakeR36S-OS's port: ports/sm64/ with the game, its archive, the extractor's description of the ROM (config.yml,
# assets/), libs, the setup screen and the launcher, plus its Puppy entry and icon, as one zip for HOME's root
build_fakers36s() {
    local v s a zip f
    [ -f "$OUT/$ELF" ] && [ -f "$OUT/ghostship.o2r" ] && [ -d "$OUT/libs" ] ||
        { echo "no out/$PORT: ./build.sh game, port and libs first"; exit 1; }
    s=/repo/out/fakers36s
    a=$s/ports/$PORT
    rm -rf "$s"
    mkdir -p "$a/licenses" "$s/.local/share/applications" "$s/.local/share/icons"
    cp "$OUT/$ELF" "$OUT/ghostship.o2r" "$a/"
    cp -r "$OUT/libs" "$a/"
    cp "$SRC/config.yml" "$a/"
    cp -r "$SRC/assets" "$a/assets"
    cp -r "$HERE/app/fonts" "$HERE/app/common.sh" "$HERE/app/sm64.sh" "$HERE/app/run.sh" "$HERE/app/defaults.json" \
        "$HERE/app/icon.png" "$a/"
    chmod 755 "$a/run.sh" "$a/sm64.sh" "$a/$ELF"
    arm-linux-gnueabihf-gcc $ARMFLAGS -O2 -Wall -D_REENTRANT -I/usr/include/SDL2 "$HERE/native/setup.c" -o "$a/setup" \
        -lSDL2 -lSDL2_ttf
    arm-linux-gnueabihf-strip "$a/setup"
    cp "$a/setup" "$OUT/setup"
    cp "$HERE/app/icon.png" "$s/.local/share/icons/$PORT.png"
    v=${APP_VERSION:-$(git -c safe.directory='*' -C /repo describe --tags --always --dirty)}
    sed "s/@VERSION@/$v/" "$HERE/app/sm64.puppy" > "$s/.local/share/applications/$PORT.puppy"

    cp "$HERE/LICENSE" "$a/licenses/LICENSE.port.txt"
    cp "$HERE"/licenses/*.txt "$a/licenses/"
    cp "$SRC/LICENSE.md" "$a/licenses/LICENSE.ghostship.txt"
    cp "$SRC/libultraship/LICENSE" "$a/licenses/LICENSE.libultraship.txt"
    [ ! -f "$SRC/Torch/LICENSE" ] || cp "$SRC/Torch/LICENSE" "$a/licenses/LICENSE.torch.txt"
    cp "$BLD/libzip-src/LICENSE" "$a/licenses/LICENSE.libzip.txt"
    for f in "$a"/libs/*; do
        [ -e "$f" ] || continue
        f=$(dpkg -S "$(basename "$f")" 2>/dev/null | grep ':armhf:' | head -n 1 | cut -d: -f1)
        [ -z "$f" ] || cp "/usr/share/doc/$f:armhf/copyright" "$a/licenses/$f.copyright.txt" 2>/dev/null ||
            cp "/usr/share/doc/$f/copyright" "$a/licenses/$f.copyright.txt"
    done

    # nothing a FAT card can't hold: links, names it refuses, names that differ only in case
    bad=$(cd "$s" && { find ports .local -type l; find ports .local -name '*[\\:*?"<>|]*'; find ports .local | tr A-Z a-z | sort | uniq -d; })
    [ -z "$bad" ] || { echo "not for a FAT card:"; echo "$bad"; exit 1; }
    # and nothing of the game: no ROM, no extracted archive
    bad=$(cd "$s" && find . -iname '*.z64' -o -iname '*.n64' -o -iname '*.v64' -o -iname 'sm64.o2r')
    [ -z "$bad" ] || { echo "game files in the package:"; echo "$bad"; exit 1; }
    zip=/repo/out/FakeR36S-SM64-$v.zip
    rm -f "$zip"
    (cd "$s" && python3 -c 'import os, stat, sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
    for top in ("ports", ".local"):
        for root, dirs, files in os.walk(top):
            dirs.sort()
            for f in sorted(files):
                p = os.path.join(root, f)
                i = zipfile.ZipInfo.from_file(p)
                i.compress_type = zipfile.ZIP_DEFLATED
                with open(p, "rb") as fh:
                    z.writestr(i, fh.read(), compresslevel=9)' "$zip")
    echo "== out/${zip##*/}: unzip into the root of FakeR36S-OS's HOME, $(find "$a" -type f | wc -l) files," \
        "$(du -sm "$a" | cut -f1) MB unpacked, $(($(stat -c %s "$zip") / 1048576)) MB zipped"
}

# The packaged port under qemu-arm on Xvfb, GLES2 on Mesa's llvmpipe, without a ROM: Ghostship starts, opens its
# GLES2 context, builds its ImGui shaders and waits in its "No O2R files" prompt. A screenshot every 30 s for $1
# seconds; fails if the game died or never reported its GLES2 renderer.
smoke() {
    local secs=${1:-180} run=/tmp/sm64-run shots=/repo/out/smoke t xvfb game alive=1
    rm -rf "$run" "$shots"; mkdir -p "$run/home" "$shots"
    cp -r /repo/out/fakers36s/ports/sm64/. "$run/"
    cp "$run/defaults.json" "$run/home/ghostship.cfg.json"
    Xvfb :9 -screen 0 640x480x24 -nolisten tcp & xvfb=$!
    sleep 2
    (cd "$run" && SHIP_HOME=$run/home DISPLAY=:9 SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy QEMU_LD_PREFIX=/ \
        LD_LIBRARY_PATH=$run/libs exec qemu-arm ./Ghostship > "$shots/stdout.log" 2>&1) & game=$!
    for ((t = 30; t <= secs; t += 30)); do
        sleep 30
        kill -0 $game 2>/dev/null || { echo "Ghostship exited before ${t}s"; alive=0; break; }
        DISPLAY=:9 import -window root "$shots/t$t.png"
    done
    kill $game 2>/dev/null || true
    sleep 2
    kill -9 $game 2>/dev/null || true
    kill $xvfb 2>/dev/null || true
    cp "$run/home/logs/"*.log "$shots/" 2>/dev/null || true
    tail -n 40 "$shots/stdout.log"
    ls -l "$shots"
    [ $alive = 1 ] && grep -q "GLES2: " "$shots"/*.log
}

source_tree
case "${1:-all}" in
    game) game ;;
    port) port_o2r ;;
    shaders) shaders ;;
    libs) libs ;;
    check) check ;;
    smoke) smoke "${2:-}" ;;
    lima) lima ;;
    fakers36s) build_fakers36s ;;
    all) game; port_o2r; libs; build_fakers36s; check ;;
    *) echo "usage: $0 [game|port|shaders|libs|check|fakers36s]" >&2; exit 1 ;;
esac
