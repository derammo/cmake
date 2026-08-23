include_guard()

# template expansion script, run directly by node without compilation
set(DERAMMO_NPM_GENERATOR "${CMAKE_SOURCE_DIR}/cmake/scripts/generate_npm_package_json.ts")

# `npm install` with the lines that only say nothing happened filtered out
set(DERAMMO_NPM_INSTALL ${CMAKE_COMMAND} -P "${CMAKE_SOURCE_DIR}/cmake/scripts/npm_install.cmake")

# internal: expand _package_template.json into package.json in the current source
# directory; DERAMMO_NPM_WORKSPACES_JSON is a JSON array of workspace folders when
# generating for a workspace root, or empty
function(derammo_npm_generate DERAMMO_NPM_WORKSPACES_JSON)
	# template search path: package local templates, then workspace root templates,
	# then standard templates from this submodule; missing folders are ignored by
	# the generator
	set(DERAMMO_NPM_TEMPLATE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/templates")
	if(DEFINED DERAMMO_NPM_WORKSPACE_ROOT)
		list(APPEND DERAMMO_NPM_TEMPLATE_DIRS "${DERAMMO_NPM_WORKSPACE_ROOT}/templates")
	endif()
	list(APPEND DERAMMO_NPM_TEMPLATE_DIRS "${CMAKE_SOURCE_DIR}/cmake/npm_package_templates")
	list(REMOVE_DUPLICATES DERAMMO_NPM_TEMPLATE_DIRS)
	string(JOIN ":" DERAMMO_NPM_TEMPLATE_PATH ${DERAMMO_NPM_TEMPLATE_DIRS})

	# rerun cmake when any input that may have contributed changes: the local
	# template and the generator that expands it
	set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
		CMAKE_CONFIGURE_DEPENDS
			"${CMAKE_CURRENT_SOURCE_DIR}/_package_template.json"
			"${DERAMMO_NPM_GENERATOR}")

	# the generated file is a dependency on itself: generation runs at configure
	# time, so nothing else can notice that package.json is missing, and it stays
	# missing until some unrelated input happens to trigger a reconfigure
	set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
		CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/package.json")

	# CONFIGURE_DEPENDS reruns the glob at build time, so adding a template to a
	# search path directory triggers a reconfigure, not just editing an existing one
	foreach(DERAMMO_NPM_TEMPLATE_DIR ${DERAMMO_NPM_TEMPLATE_DIRS})
		file(GLOB DERAMMO_NPM_TEMPLATES CONFIGURE_DEPENDS "${DERAMMO_NPM_TEMPLATE_DIR}/_package_template*.json")
		set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
			CMAKE_CONFIGURE_DEPENDS ${DERAMMO_NPM_TEMPLATES})
	endforeach()

	message(STATUS "generating package.json in '${CMAKE_CURRENT_SOURCE_DIR}'")
	execute_process(
		COMMAND ${CMAKE_COMMAND} -E env
			"DERAMMO_NPM_PACKAGE_TEMPLATE_PATH=${DERAMMO_NPM_TEMPLATE_PATH}"
			"DERAMMO_NPM_WORKSPACES=${DERAMMO_NPM_WORKSPACES_JSON}"
			node "${DERAMMO_NPM_GENERATOR}"
		WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
		COMMAND_ERROR_IS_FATAL ANY
	)

	# on demand regeneration with the same search path cmake computed, so that a
	# single package can be refreshed without reconfiguring the whole tree; not in
	# ALL, since configure already generates on every run
	file(RELATIVE_PATH DERAMMO_RELATIVE_CURRENT_SOURCE_DIR "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
	string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX "${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR}")
	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_package_json
		COMMAND ${CMAKE_COMMAND} -E env
			"DERAMMO_NPM_PACKAGE_TEMPLATE_PATH=${DERAMMO_NPM_TEMPLATE_PATH}"
			"DERAMMO_NPM_WORKSPACES=${DERAMMO_NPM_WORKSPACES_JSON}"
			node "${DERAMMO_NPM_GENERATOR}"
		WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
		COMMENT "regenerating package.json in '${CMAKE_CURRENT_SOURCE_DIR}'"
		VERBATIM
	)
endfunction()

# internal: compute the ctest labels for the package in DERAMMO_NPM_PACKAGE_DIR:
# "npm" for the provider, plus the name of each known test framework found in
# the generated package.json's devDependencies
function(derammo_npm_test_labels DERAMMO_NPM_PACKAGE_DIR DERAMMO_NPM_LABELS_OUT)
	set(DERAMMO_NPM_LABELS npm)
	file(READ "${DERAMMO_NPM_PACKAGE_DIR}/package.json" DERAMMO_NPM_PACKAGE_JSON)
	foreach(DERAMMO_NPM_FRAMEWORK vitest jest mocha)
		string(JSON DERAMMO_NPM_FRAMEWORK_VERSION ERROR_VARIABLE DERAMMO_NPM_JSON_ERROR
			GET "${DERAMMO_NPM_PACKAGE_JSON}" devDependencies ${DERAMMO_NPM_FRAMEWORK})
		if(NOT DERAMMO_NPM_JSON_ERROR)
			list(APPEND DERAMMO_NPM_LABELS ${DERAMMO_NPM_FRAMEWORK})
		endif()
	endforeach()
	set(${DERAMMO_NPM_LABELS_OUT} "${DERAMMO_NPM_LABELS}" PARENT_SCOPE)
endfunction()

# internal: label the registered ctest entry DERAMMO_NPM_TEST for the package
# in DERAMMO_NPM_PACKAGE_DIR and configure its output: no color, and JUnit XML
# in DERAMMO_JUNIT_DIR via whatever mechanism the package's test framework
# offers; vitest reads DERAMMO_JUNIT_FILE in the generated vitest.config.ts,
# jest-junit reads its own variable, and a package without any known framework
# is assumed to use `node --test`, which takes reporters from NODE_OPTIONS
function(derammo_npm_test_properties DERAMMO_NPM_TEST DERAMMO_NPM_PACKAGE_DIR)
	derammo_npm_test_labels("${DERAMMO_NPM_PACKAGE_DIR}" DERAMMO_NPM_LABELS)
	set_tests_properties(${DERAMMO_NPM_TEST} PROPERTIES LABELS "${DERAMMO_NPM_LABELS}")
	derammo_test_output(${DERAMMO_NPM_TEST})

	set(DERAMMO_NPM_JUNIT_FILE "${DERAMMO_JUNIT_DIR}/${DERAMMO_NPM_TEST}.xml")
	if("jest" IN_LIST DERAMMO_NPM_LABELS)
		set_property(TEST ${DERAMMO_NPM_TEST} APPEND PROPERTY ENVIRONMENT
			"JEST_JUNIT_OUTPUT_FILE=${DERAMMO_NPM_JUNIT_FILE}")
	endif()
	list(LENGTH DERAMMO_NPM_LABELS DERAMMO_NPM_LABEL_COUNT)
	if(DERAMMO_NPM_LABEL_COUNT EQUAL 1)
		set_property(TEST ${DERAMMO_NPM_TEST} APPEND PROPERTY ENVIRONMENT
			"NODE_OPTIONS=--test-reporter=spec --test-reporter-destination=stdout --test-reporter=junit --test-reporter-destination=${DERAMMO_NPM_JUNIT_FILE}")
	endif()
endfunction()

# declare an npm package in the current source directory, generating its
# package.json from _package_template.json at configure time; inside a workspace
# the workspace root builds and tests all packages, so a standalone package
# creates its own targets
function(derammo_npm)
	derammo_npm_generate("")

	# register with the enclosing workspace, if any
	set_property(GLOBAL APPEND PROPERTY DERAMMO_NPM_PACKAGES "${CMAKE_CURRENT_SOURCE_DIR}")

	# the clean target removes our npm installation
	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${CMAKE_CURRENT_SOURCE_DIR}/node_modules")

	if(NOT DEFINED DERAMMO_NPM_WORKSPACE_ROOT)
		file(RELATIVE_PATH DERAMMO_RELATIVE_CURRENT_SOURCE_DIR "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
		string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX "${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR}")
		add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_npm ALL
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			COMMAND ${DERAMMO_NPM_INSTALL}
			COMMAND npm run build --if-present --silent
			COMMENT "building npm package in '${CMAKE_CURRENT_SOURCE_DIR}'"
		)
		add_test(NAME ${DERAMMO_CURRENT_TARGET_PREFIX}_npm
			COMMAND npm run test --if-present --silent
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		)
		derammo_npm_test_properties(${DERAMMO_CURRENT_TARGET_PREFIX}_npm "${CMAKE_CURRENT_SOURCE_DIR}")
	endif()
endfunction()

# declare the current source directory as an npm workspace root: automatically
# adds all subdirectories that have a CMakeLists.txt, generates a package.json
# whose workspaces list contains every folder below that declared derammo_npm(),
# and builds and tests all workspaces via npm from here
function(derammo_workspaces_auto)
	# visible to all subdirectories added below
	set(DERAMMO_NPM_WORKSPACE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")

	file(GLOB_RECURSE DERAMMO_NPM_CANDIDATES RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "CMakeLists.txt")
	foreach(DERAMMO_NPM_CANDIDATE ${DERAMMO_NPM_CANDIDATES})
	  if(NOT DERAMMO_NPM_CANDIDATE MATCHES "^CMakeLists.txt$" AND NOT DERAMMO_NPM_CANDIDATE MATCHES "/node_modules/")
			file(READ "${DERAMMO_NPM_CANDIDATE}" DERAMMO_NPM_CANDIDATE_CONTENT)
			if(DERAMMO_NPM_CANDIDATE_CONTENT MATCHES "derammo_npm\\(")
				get_filename_component(DERAMMO_NPM_SUBDIRECTORY "${DERAMMO_NPM_CANDIDATE}" DIRECTORY)
				add_subdirectory("${DERAMMO_NPM_SUBDIRECTORY}")
			endif()
		endif()
	endforeach()

	# collect the packages that registered from within this workspace
	get_property(DERAMMO_NPM_PACKAGES GLOBAL PROPERTY DERAMMO_NPM_PACKAGES)
	set(DERAMMO_NPM_WORKSPACE_FOLDERS "")
	set(DERAMMO_NPM_MEMBER_DIRS "")
	foreach(DERAMMO_NPM_PACKAGE ${DERAMMO_NPM_PACKAGES})
		file(RELATIVE_PATH DERAMMO_NPM_RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${DERAMMO_NPM_PACKAGE}")
		if(NOT DERAMMO_NPM_RELATIVE MATCHES "^\\.\\.")
			list(APPEND DERAMMO_NPM_WORKSPACE_FOLDERS "\"${DERAMMO_NPM_RELATIVE}\"")
			list(APPEND DERAMMO_NPM_MEMBER_DIRS "${DERAMMO_NPM_PACKAGE}")
		endif()
	endforeach()
	string(JOIN "," DERAMMO_NPM_WORKSPACES_JOINED ${DERAMMO_NPM_WORKSPACE_FOLDERS})
	derammo_npm_generate("[${DERAMMO_NPM_WORKSPACES_JOINED}]")

	# the clean target removes our npm installation
	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${CMAKE_CURRENT_SOURCE_DIR}/node_modules")

	file(RELATIVE_PATH DERAMMO_RELATIVE_CURRENT_SOURCE_DIR "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
	string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX "${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR}")
	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_npm ALL
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		COMMAND ${DERAMMO_NPM_INSTALL}
		COMMAND npm run build --workspaces --if-present --silent
		COMMENT "building npm workspace in '${CMAKE_CURRENT_SOURCE_DIR}'"
	)
	# one test per member, run from the root so hoisted dependencies resolve
	foreach(DERAMMO_NPM_MEMBER_DIR ${DERAMMO_NPM_MEMBER_DIRS})
		file(RELATIVE_PATH DERAMMO_NPM_MEMBER_RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${DERAMMO_NPM_MEMBER_DIR}")
		string(REPLACE "/" "_" DERAMMO_NPM_MEMBER_TEST "${DERAMMO_CURRENT_TARGET_PREFIX}_${DERAMMO_NPM_MEMBER_RELATIVE}")
		add_test(NAME ${DERAMMO_NPM_MEMBER_TEST}
			COMMAND npm run test --workspace "${DERAMMO_NPM_MEMBER_RELATIVE}" --if-present --silent
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		)
		derammo_npm_test_properties(${DERAMMO_NPM_MEMBER_TEST} "${DERAMMO_NPM_MEMBER_DIR}")
	endforeach()

	# export state for a subsequent derammo_npm_install() call from the same directory
	set(DERAMMO_NPM_WORKSPACE_TARGET_PREFIX "${DERAMMO_CURRENT_TARGET_PREFIX}" PARENT_SCOPE)
	set(DERAMMO_NPM_WORKSPACE_MEMBER_DIRS "${DERAMMO_NPM_MEMBER_DIRS}" PARENT_SCOPE)
endfunction()

# stage the workspace's production install closure and package it as a CPack
# component: after the workspace build, npm pack each member (honors "files" in
# package.json), then npm install all tarballs into a staging prefix, producing
# real files (no workspace symlinks) with sibling dependencies resolved from
# the tarballs instead of the registry; call after derammo_workspaces_auto()
# in the same directory
#
# derammo_npm_install(COMPONENT <c> [DESTINATION <d>] [DEPENDS <deb-depends>] [NPM_INSTALL_FLAGS ...])
#   defaults: DESTINATION ${DERAMMO_INSTALL_LIBDIR}, DEPENDS "nodejs (>= 20)"
#
# macro so the CPACK_DEBIAN_..._PACKAGE_DEPENDS variable lands in the parent
# scope, where the top-level include(CPack) can see it
macro(derammo_npm_install)
	_derammo_npm_install_stage(${ARGN})
	string(TOUPPER "${DERAMMO_NPM_INSTALL_COMPONENT}" DERAMMO_NPM_INSTALL_COMPONENT_UPPER)
	set(CPACK_DEBIAN_${DERAMMO_NPM_INSTALL_COMPONENT_UPPER}_PACKAGE_DEPENDS "${DERAMMO_NPM_INSTALL_DEPENDS}")
	set(CPACK_DEBIAN_${DERAMMO_NPM_INSTALL_COMPONENT_UPPER}_PACKAGE_DEPENDS "${DERAMMO_NPM_INSTALL_DEPENDS}" PARENT_SCOPE)
endmacro()

# internal: create the staging target and install rule for derammo_npm_install,
# exporting the parsed COMPONENT and DEPENDS values to the caller
function(_derammo_npm_install_stage)
	cmake_parse_arguments(PARSE_ARGV 0 DERAMMO_NPM_INSTALL "" "COMPONENT;DESTINATION;DEPENDS" "NPM_INSTALL_FLAGS")
	if(NOT DERAMMO_NPM_INSTALL_COMPONENT)
		message(FATAL_ERROR "derammo_npm_install: COMPONENT is required")
	endif()
	if(NOT DERAMMO_NPM_INSTALL_DESTINATION)
		set(DERAMMO_NPM_INSTALL_DESTINATION "${DERAMMO_INSTALL_LIBDIR}")
	endif()
	if(NOT DEFINED DERAMMO_NPM_INSTALL_DEPENDS)
		set(DERAMMO_NPM_INSTALL_DEPENDS "nodejs (>= 20)")
	endif()
	if(NOT DEFINED DERAMMO_NPM_WORKSPACE_TARGET_PREFIX)
		message(FATAL_ERROR "derammo_npm_install: call derammo_workspaces_auto() first in the same directory")
	endif()

	set(DERAMMO_NPM_STAGE "${CMAKE_CURRENT_BINARY_DIR}/npm_install")

	# compute the exact tarball names npm pack will produce from each member's
	# generated package.json: @scope/name -> scope-name-version.tgz
	set(DERAMMO_NPM_TARBALL_PATHS "")
	foreach(DERAMMO_NPM_MEMBER_DIR ${DERAMMO_NPM_WORKSPACE_MEMBER_DIRS})
		file(READ "${DERAMMO_NPM_MEMBER_DIR}/package.json" DERAMMO_NPM_PACKAGE_JSON)
		string(JSON DERAMMO_NPM_PACKAGE_NAME GET "${DERAMMO_NPM_PACKAGE_JSON}" name)
		string(JSON DERAMMO_NPM_PACKAGE_VERSION GET "${DERAMMO_NPM_PACKAGE_JSON}" version)
		string(REPLACE "@" "" DERAMMO_NPM_TARBALL_BASE "${DERAMMO_NPM_PACKAGE_NAME}")
		string(REPLACE "/" "-" DERAMMO_NPM_TARBALL_BASE "${DERAMMO_NPM_TARBALL_BASE}")
		list(APPEND DERAMMO_NPM_TARBALL_PATHS "${DERAMMO_NPM_STAGE}/tarballs/${DERAMMO_NPM_TARBALL_BASE}-${DERAMMO_NPM_PACKAGE_VERSION}.tgz")
	endforeach()

	# minimal manifest for the staging prefix, so npm install works outside any package
	file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/npm_deploy_package.json"
		"{\"name\":\"deploy\",\"version\":\"0.0.0\",\"private\":true}\n")

	message(STATUS "staging npm production install from '${CMAKE_CURRENT_SOURCE_DIR}' for component '${DERAMMO_NPM_INSTALL_COMPONENT}'")
	add_custom_target(${DERAMMO_NPM_WORKSPACE_TARGET_PREFIX}_npm_install ALL
		WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
		COMMAND ${CMAKE_COMMAND} -E rm -rf "${DERAMMO_NPM_STAGE}"
		COMMAND ${CMAKE_COMMAND} -E make_directory "${DERAMMO_NPM_STAGE}/tarballs" "${DERAMMO_NPM_STAGE}/deploy"
		COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/npm_deploy_package.json" "${DERAMMO_NPM_STAGE}/deploy/package.json"
		COMMAND npm pack --workspaces --pack-destination "${DERAMMO_NPM_STAGE}/tarballs"
		COMMAND ${CMAKE_COMMAND} -E chdir "${DERAMMO_NPM_STAGE}/deploy"
			npm install --omit=dev --no-audit --no-fund ${DERAMMO_NPM_INSTALL_NPM_INSTALL_FLAGS} ${DERAMMO_NPM_TARBALL_PATHS}
	)

	# stage after the workspace build, so dist/ exists in every member
	add_dependencies(${DERAMMO_NPM_WORKSPACE_TARGET_PREFIX}_npm_install ${DERAMMO_NPM_WORKSPACE_TARGET_PREFIX}_npm)

	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${DERAMMO_NPM_STAGE}")

	# no trailing slash: the package gets <destination>/node_modules/...
	install(DIRECTORY "${DERAMMO_NPM_STAGE}/deploy/node_modules"
		COMPONENT ${DERAMMO_NPM_INSTALL_COMPONENT}
		DESTINATION ${DERAMMO_NPM_INSTALL_DESTINATION}
		# keeps execute bits on node_modules/.bin entries
		USE_SOURCE_PERMISSIONS
	)

	# export parsed values for the enclosing macro
	set(DERAMMO_NPM_INSTALL_COMPONENT "${DERAMMO_NPM_INSTALL_COMPONENT}" PARENT_SCOPE)
	set(DERAMMO_NPM_INSTALL_DEPENDS "${DERAMMO_NPM_INSTALL_DEPENDS}" PARENT_SCOPE)
endfunction()
