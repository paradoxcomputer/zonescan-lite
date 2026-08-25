cmake_minimum_required(VERSION 3.19)
project(ZonescanLitePlugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Single-source the version: metadata.json is the manifest the bundler ships, so read the
# version straight out of it rather than repeating it in C++. It used to be hand-typed into
# the User-Agent in two places, where it silently drifted from the manifest.
# Directory-scoped, so it applies to the targets logos_module() creates below.
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/metadata.json" _zs_metadata)
string(JSON _zs_version GET "${_zs_metadata}" version)
add_compile_definitions(ZONESCAN_LITE_VERSION="${_zs_version}")
message(STATUS "zonescan_lite version ${_zs_version} (from metadata.json)")

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/cmake/LogosModule.cmake")
    include(cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# Universal ui_qml module: author only the .rep view contract + the *Backend TU.
# REP_FILE runs repc (=> rep_zonescan_lite_source.h, ZonescanLiteSimpleSource); the
# *Plugin/*Interface glue + no dependency wrappers are needed.
logos_module(
    NAME zonescan_lite
    REP_FILE src/zonescan_lite.rep
    SOURCES
        src/zonescan_lite_backend.h
        src/zonescan_lite_backend.cpp
    INCLUDE_DIRS
        src
)
