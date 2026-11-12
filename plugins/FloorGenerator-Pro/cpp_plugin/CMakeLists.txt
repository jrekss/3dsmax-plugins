cmake_minimum_required(VERSION 3.20)
project(FloorGenerator_v2 LANGUAGES CXX RC)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT DEFINED MAXSDK_DIR OR NOT EXISTS "${MAXSDK_DIR}/include/max.h")
    if(DEFINED ENV{ADSK_3DSMAX_SDK_2027})
        set(MAXSDK_DIR "$ENV{ADSK_3DSMAX_SDK_2027}")
    elseif(EXISTS "C:/Program Files/Autodesk/3ds Max 2027 SDK/maxsdk/include/max.h")
        set(MAXSDK_DIR "C:/Program Files/Autodesk/3ds Max 2027 SDK/maxsdk")
    else()
        message(FATAL_ERROR "MAXSDK_DIR is not set or invalid. Pass -DMAXSDK_DIR=...")
    endif()
endif()

add_library(FloorGenerator_v2 SHARED
    src/DllEntry.cpp
    src/FloorGenerator.cpp
    src/FloorGenerator.h
    src/FloorGenerator.rc
    src/FloorGenerator.def
    src/resource.h
)

set_target_properties(FloorGenerator_v2 PROPERTIES
    SUFFIX ".dlm"
    PREFIX ""
)

target_include_directories(FloorGenerator_v2 PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${MAXSDK_DIR}/include"
)

target_compile_definitions(FloorGenerator_v2 PRIVATE
    WIN32
    _WINDOWS
    _USRDLL
    UNICODE
    _UNICODE
    NOMINMAX
    _CRT_SECURE_NO_WARNINGS
    ISOLATION_AWARE_ENABLED=1
)

target_compile_options(FloorGenerator_v2 PRIVATE
    /W3
    /MP
    /O2
    /Zc:wchar_t
)

target_link_directories(FloorGenerator_v2 PRIVATE
    "${MAXSDK_DIR}/lib/x64/Release"
)

target_link_libraries(FloorGenerator_v2 PRIVATE
    core.lib
    geom.lib
    gfx.lib
    mesh.lib
    maxutil.lib
    maxscrpt.lib
    paramblk2.lib
    comctl32.lib
)
