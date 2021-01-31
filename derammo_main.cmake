cmake_minimum_required(VERSION 3.13.0)

# minimum C++ requirement for google test
set(CMAKE_CXX_STANDARD 11)

# modules may be loaded from here
set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH};${CMAKE_SOURCE_DIR}/cmake)
message(STATUS "module path is: ${CMAKE_MODULE_PATH}")

# our path preferences by platform
include("derammo_paths")

# no support for rerunning cmake from build directory
set(CMAKE_SUPPRESS_REGENERATION true)

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

# helper to add a default gtest binary
function(derammo_add_gtest_target DERAMMO_TARGET)
    set(DERAMMO_GTEST_TARGET ${DERAMMO_TARGET}_gtest)
    set(DERAMMO_GTEST_TARGET ${DERAMMO_GTEST_TARGET} PARENT_SCOPE)
    
    # create testing target
    add_executable(${DERAMMO_GTEST_TARGET})
    target_sources(${DERAMMO_GTEST_TARGET} PUBLIC ${DERAMMO_PUBLIC_SOURCES})
    target_sources(${DERAMMO_GTEST_TARGET} PUBLIC ${DERAMMO_INTERFACE_SOURCES})
    target_sources(${DERAMMO_GTEST_TARGET} PUBLIC ${DERAMMO_PRIVATE_SOURCES})
    target_sources(${DERAMMO_GTEST_TARGET} PUBLIC ${DERAMMO_GTEST_SOURCES})
    target_link_libraries(${DERAMMO_GTEST_TARGET} gtest_main)
endfunction()

# automatically set up a library using all sources found
macro(derammo_add_library_auto DERAMMO_TARGET DERAMMO_LIBRARY_TYPE)
    add_library(${DERAMMO_TARGET} ${DERAMMO_LIBRARY_TYPE})
  
    # include paths for a library
    target_include_directories(${DERAMMO_TARGET} PUBLIC include)
    target_include_directories(${DERAMMO_TARGET} PRIVATE src)
    
    # automatically add all sources
    derammo_scan_library_sources(${DERAMMO_TARGET} ${DERAMMO_LIBRARY_TYPE})
    derammo_add_sources(${DERAMMO_TARGET})

    # create gtest target if any testing sources are found
    if (NOT "${DERAMMO_GTEST_SOURCES}" STREQUAL "")
        derammo_add_gtest_target(${DERAMMO_TARGET})
    endif()
endmacro()