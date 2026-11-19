# The build image: Debian with the armhf cross compiler and the libraries Ghostship links (armhf), the native ones for
# Torch (which packs ghostship.o2r) and glslang (which checks the GLES2 shaders). spdlog, tinyxml2 and libzip are left
# out on purpose: they are fetched (cmake/ghostship-deps.cmake) or built (build.sh) and linked statically.
# From FakeR36S-Ocarina's.
FROM debian:trixie

RUN dpkg --add-architecture armhf && apt-get update && apt-get install -y --no-install-recommends \
    build-essential crossbuild-essential-armhf binutils-arm-linux-gnueabihf pkg-config git ca-certificates curl \
    file zip unzip python3 cmake ninja-build lsb-release glslang-tools \
    zlib1g-dev libbz2-dev libpng-dev nlohmann-json3-dev \
    zlib1g-dev:armhf libbz2-dev:armhf libpng-dev:armhf libsdl2-dev:armhf libsdl2-ttf-dev:armhf \
    libegl-dev:armhf libgles-dev:armhf \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo
