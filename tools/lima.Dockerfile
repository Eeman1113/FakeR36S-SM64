# build.sh lima's image: the build image plus Mesa built for this machine with only the lima (Mali-400) driver and its
# drm-shim, which fakes a Mali-400 so that its real shader compiler runs here (Mesa's shader-db does the same).
FROM fakers36s-sm64

ARG MESA=mesa-25.3.6
RUN apt-get update && apt-get install -y --no-install-recommends meson python3-mako python3-yaml python3-packaging \
    bison flex libdrm-dev libexpat1-dev zlib1g-dev libegl-dev libgles-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone -q --depth 1 --branch $MESA https://gitlab.freedesktop.org/mesa/mesa.git /opt/mesa-src \
    && cd /opt/mesa-src \
    && meson setup build -Dprefix=/opt/mesa -Dbuildtype=release -Db_ndebug=true \
        -Dgallium-drivers=lima -Dvulkan-drivers= -Dplatforms= -Dglx=disabled -Degl=enabled -Dgbm=enabled \
        -Dgles1=disabled -Dgles2=enabled -Dopengl=true -Dglvnd=disabled -Dllvm=disabled -Dtools=drm-shim \
        -Dvalgrind=disabled -Dlibunwind=disabled -Dzstd=disabled -Dxmlconfig=disabled \
    && ninja -C build install \
    && cp build/src/gallium/drivers/lima/drm-shim/liblima_noop_drm_shim.so /opt/mesa/ \
    && rm -rf /opt/mesa-src
