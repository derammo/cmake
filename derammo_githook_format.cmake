include_guard()

# install the format_all script as a git pre-commit hook, so all packages are
# formatted before every commit; only on platforms that have /bin/bash (not
# native Windows)
if(EXISTS "/bin/bash")
	# locate the hooks directory of the enclosing checkout; --git-path resolves
	# worktrees and submodule gitfiles, and may return a relative path
	execute_process(
		COMMAND git rev-parse --git-path hooks
		WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
		RESULT_VARIABLE DERAMMO_GITHOOK_GIT_RESULT
		OUTPUT_VARIABLE DERAMMO_GITHOOK_HOOKS_DIR
		ERROR_QUIET
		OUTPUT_STRIP_TRAILING_WHITESPACE
	)
	if(DERAMMO_GITHOOK_GIT_RESULT EQUAL 0)
		get_filename_component(DERAMMO_GITHOOK_HOOKS_DIR "${DERAMMO_GITHOOK_HOOKS_DIR}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")

		if(EXISTS "${DERAMMO_GITHOOK_HOOKS_DIR}/pre-commit")
			# an existing hook is never overwritten, no matter what installed it
			message(STATUS "pre-commit hook already exists; not installing the format hook")
		else()
			# the hook is a frozen copy of the script, not a reference into the
			# work tree, so pulling new repo content cannot change what runs at
			# commit time; updating requires deleting the hook and rebuilding;
			# no DEPENDS, so the rule runs only while the hook does not exist
			add_custom_command(OUTPUT "${DERAMMO_GITHOOK_HOOKS_DIR}/pre-commit"
				COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_LIST_DIR}/scripts/format_all.sh" "${DERAMMO_GITHOOK_HOOKS_DIR}/pre-commit"
				COMMENT "installing git pre-commit format hook"
				VERBATIM
			)
			add_custom_target(derammo_githook_format ALL
				DEPENDS "${DERAMMO_GITHOOK_HOOKS_DIR}/pre-commit"
			)
		endif()
	else()
		message(STATUS "not a git checkout; skipping format pre-commit hook")
	endif()
endif()
