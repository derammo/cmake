# to be included before cmake/derammo_main.cmake, if Google test is used

# download and import, without submodule
include(FetchContent)
FetchContent_Declare(
    googletest
    GIT_REPOSITORY https://github.com/google/googletest.git
    GIT_TAG        v1.14.0
)
if(WIN32)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
endif()
FetchContent_MakeAvailable(googletest)
include(GoogleTest)

# helper to add a default gtest binary
function(derammo_add_gtest_target DERAMMO_TARGET)
    set(DERAMMO_GTEST_TARGET ${DERAMMO_TARGET}_gtest)
    set(DERAMMO_GTEST_TARGET ${DERAMMO_GTEST_TARGET} PARENT_SCOPE)
    
    # create testing target, linking against the library and gtest glue
    add_executable(${DERAMMO_GTEST_TARGET})
    target_sources(${DERAMMO_GTEST_TARGET} PUBLIC ${DERAMMO_INTERFACE_SOURCES})
    target_sources(${DERAMMO_GTEST_TARGET} PRIVATE ${DERAMMO_GTEST_SOURCES})
    target_link_libraries(${DERAMMO_GTEST_TARGET} ${DERAMMO_TARGET} gtest_main)
    file(MAKE_DIRECTORY ${DERAMMO_RUNTIME_DIR})
    gtest_discover_tests(${DERAMMO_GTEST_TARGET}
        WORKING_DIRECTORY ${DERAMMO_RUNTIME_DIR}
        TEST_PREFIX ${DERAMMO_TARGET}_)
endfunction()

# helper for projects that just want to add all gtest sources, regardless of whether they use fixed sources for production code
function(derammo_add_gtest_auto DERAMMO_TARGET DERAMMO_LIBRARY_TYPE)
    derammo_scan_gtest_sources(${DERAMMO_TARGET} ${DERAMMO_LIBRARY_TYPE})
    derammo_add_gtest_target(${DERAMMO_TARGET})
endfunction()