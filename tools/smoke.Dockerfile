# build.sh smoke's image: the build image plus Xvfb, ImageMagick, qemu-arm and Mesa's llvmpipe for armhf, which the
# game runs on (GLES2 through Mesa's own GLSL compiler, the one lima uses too). From FakeR36S-Ocarina's shot.Dockerfile.
FROM fakers36s-sm64

RUN apt-get update && apt-get install -y --no-install-recommends xvfb imagemagick qemu-user \
    libegl-mesa0:armhf libgl1-mesa-dri:armhf libgles2:armhf libglx-mesa0:armhf libgl1:armhf \
    && rm -rf /var/lib/apt/lists/*
