function(derammo_assert_non_empty DERAMMO_VARIABLE)
  if ("${${DERAMMO_VARIABLE}}" STREQUAL "")
    message(FATAL_ERROR "unexpected: the DERAMMO_VARIABLE ${DERAMMO_VARIABLE} is empty or not set")
  endif()
endfunction()

macro(derammo_build_only_once DERAMMO_PROJECT_NAME DERAMMO_SOURCE_PATH)
  get_property(DERAMMO_ALREADY_BUILT GLOBAL PROPERTY DERAMMO_HAS_BUILT_${DERAMMO_PROJECT_NAME})
  if ("${DERAMMO_ALREADY_BUILT}" STREQUAL "")
    # note the fact that we have built this
    set_property(GLOBAL PROPERTY DERAMMO_HAS_BUILT_${DERAMMO_PROJECT_NAME} DERAMMO_SOURCE_PATH)
  else()
    # return from calling file, since this is a macro
    message(STATUS "${DERAMMO_PROJECT_NAME} has already been built from '${${DERAMMO_ALREADY_BUILT}}'; skipping")
    return()
  endif()
endmacro()

function(derammo_update_runtime DERAMMO_SOURCE)
    string(REPLACE "${CMAKE_SOURCE_DIR}/" "" DERAMMO_RELATIVE_CURRENT_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    string(REPLACE "/" "_" DERAMMO_PATH_CLEANED ${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR}/${DERAMMO_SOURCE})

    message(STATUS "searching for runtime files in ${DERAMMO_SOURCE} relative to ${CMAKE_CURRENT_SOURCE_DIR}")
    file(GLOB_RECURSE DERAMMO_FILES_${DERAMMO_PATH_CLEANED}
        LIST_DIRECTORIES false
        RELATIVE ${CMAKE_CURRENT_SOURCE_DIR}
        "${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_SOURCE}/*"
    )

    # create copy operations
    foreach(DERAMMO_FILE ${DERAMMO_FILES_${DERAMMO_PATH_CLEANED}})
        set(DERAMMO_OUTPUT "${DERAMMO_RUNTIME_DIR}/${DERAMMO_FILE}")
        get_filename_component(DERAMMO_OUTPUT_DIR "${DERAMMO_OUTPUT}" DIRECTORY)
        add_custom_command(OUTPUT ${DERAMMO_OUTPUT}
            DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_FILE}
            COMMAND ${CMAKE_COMMAND} -E make_directory ${DERAMMO_OUTPUT_DIR}
            COMMAND ${CMAKE_COMMAND} -E copy_if_different ${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_FILE} ${DERAMMO_OUTPUT}
        )
        list(APPEND DERAMMO_RUNTIME_FILES_${DERAMMO_PATH_CLEANED} "${DERAMMO_OUTPUT}")
    endforeach()

    # now depend on the files being up to date
    message(STATUS "creating runtime update target derammo_runtime_${DERAMMO_PATH_CLEANED}")
    add_custom_target("derammo_runtime_${DERAMMO_PATH_CLEANED}"
        ALL
        # list automatically interpreted correctly as multiple entries
        DEPENDS ${DERAMMO_RUNTIME_FILES_${DERAMMO_PATH_CLEANED}}
    )
endfunction()


