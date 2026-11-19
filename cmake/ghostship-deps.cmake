# Ghostship adds libultraship before Torch, and libultraship wants tinyxml2 and spdlog installed (the armhf image has
# neither). Fetch the versions Torch uses, built static, before anything looks for them. From FakeR36S-Ocarina's
# cmake/2ship-deps.cmake.
include(FetchContent)
set(tinyxml2_BUILD_TESTING OFF)
FetchContent_Declare(tinyxml2
    GIT_REPOSITORY https://github.com/leethomason/tinyxml2.git
    GIT_TAG 10.0.0
    OVERRIDE_FIND_PACKAGE)
FetchContent_Declare(spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.16.0
    OVERRIDE_FIND_PACKAGE)
FetchContent_MakeAvailable(tinyxml2 spdlog)
