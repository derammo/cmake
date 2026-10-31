include_guard()

# the `format` target of the build tree rewrites in place every source the
# build knows how to format; `make format` at the root builds it
#
# a provider that can format a language creates its own target and registers
# it with derammo_format_target, the way a test provider calls add_test; the
# deferred finalize makes `format` depend on every registered target, and
# creates `format` even when nothing registered, so the root target always
# has something to build; `format` is the one reserved name, a project does
# not define its own, like the `test` target of ctest
#
# a provider that registers from its own deferred finalize must be included
# before this module, since deferred calls run in the order they were deferred

function(derammo_format_target DERAMMO_FORMAT_TARGET)
	set_property(GLOBAL APPEND PROPERTY DERAMMO_FORMAT_TARGETS "${DERAMMO_FORMAT_TARGET}")
endfunction()

function(derammo_format_finalize)
	get_property(DERAMMO_FORMAT_TARGETS GLOBAL PROPERTY DERAMMO_FORMAT_TARGETS)
	if(DERAMMO_FORMAT_TARGETS)
		add_custom_target(format)
		add_dependencies(format ${DERAMMO_FORMAT_TARGETS})
	else()
		add_custom_target(format COMMENT "nothing registered to format")
	endif()
endfunction()

cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL derammo_format_finalize)
