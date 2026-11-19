# shadercheck: renders libultraship's GLES2 shader template (prism) for many combiner setups, for glslang to compile.
# PRISM_DIR and SPDLOG_DIR: the sources the game's build fetched (build.sh shaders).
cmake_minimum_required(VERSION 3.20)
project(shadercheck C CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_C_STANDARD 11)
file(GLOB_RECURSE PRISM_SRC ${PRISM_DIR}/src/prism/*.cpp ${PRISM_DIR}/src/prism/*.c)
add_executable(shadercheck main.cpp ${PRISM_SRC})
target_include_directories(shadercheck PRIVATE ${PRISM_DIR}/src ${PRISM_DIR}/lib ${SPDLOG_DIR}/include)
target_compile_options(shadercheck PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Wno-narrowing>)
