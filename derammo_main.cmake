cmake_minimum_required(VERSION 3.13.0)
include_guard()

if(MSVC)
    # for MSVC allow compiler extensions, which are often needed for Windows compatibility
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS ON) 

    # export all public symbols from dll, since we don't maintain export lists
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
else()
    # require C++ 17 and disable compiler extensions, which may cause issues with packaging and cross-platform support
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)
    set(CMAKE_CXX_EXTENSIONS OFF)
endif()

# modules may be loaded from here
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH};${CMAKE_SOURCE_DIR}/cmake)
message(STATUS "module path is: ${CMAKE_MODULE_PATH}")

# our path preferences by platform
include("derammo_paths")

# no support for rerunning cmake from build directory
set(CMAKE_SUPPRESS_REGENERATION true)

# enable ctest integration
enable_testing()

# standard defines
add_compile_definitions(
  $<$<NOT:$<CONFIG:Debug>>:NDEBUG>
)

# packaging defaults
set(CPACK_GENERATOR "DEB")
set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
SET(CPACK_OUTPUT_FILE_PREFIX packages)

# source globs for different project types
include("derammo_sources")

# utilities
include("derammo_utilities")

# helper to add standard sets of sources, which may be from scanning or manual
function(derammo_add_sources DERAMMO_TARGET)
    # add sources to target
    target_sources(${DERAMMO_TARGET} PUBLIC ${DERAMMO_PUBLIC_SOURCES})
    target_sources(${DERAMMO_TARGET} INTERFACE ${DERAMMO_INTERFACE_SOURCES})
    target_sources(${DERAMMO_TARGET} PRIVATE ${DERAMMO_PRIVATE_SOURCES})
endfunction()

# automatically set up a library using all sources found instead of using sources.cmake frozen list
macro(derammo_add_library_auto DERAMMO_TARGET DERAMMO_LIBRARY_TYPE)
    add_library(${DERAMMO_TARGET} ${DERAMMO_LIBRARY_TYPE})
  
    # include paths for a library
    target_include_directories(${DERAMMO_TARGET} PUBLIC include)
    target_include_directories(${DERAMMO_TARGET} PRIVATE src)
    
    # automatically add all sources
    derammo_scan_library_sources(${DERAMMO_TARGET} ${DERAMMO_LIBRARY_TYPE})
    derammo_add_sources(${DERAMMO_TARGET})
endmacro()