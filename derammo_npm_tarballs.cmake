# locally built tarball dependencies of an npm package: a dependency whose
# version is file:<path>.tgz names a tarball that `npm pack` left in the
# directory of the package that built it
#
# shared by the configure-time driver (derammo_npm.cmake) and the build-time
# install script (scripts/npm_install.cmake), so both see the same dependencies
include_guard()

# derammo_npm_tarball_dependency_list(<package-dir> <names-var> <tarballs-var>)
#
# sets <names-var> to the dependency names and <tarballs-var> to the absolute
# tarball paths, in matching order, for dependencies and devDependencies of
# the package.json in <package-dir>
function(derammo_npm_tarball_dependency_list DERAMMO_NPM_PACKAGE_DIR DERAMMO_NPM_NAMES_VAR DERAMMO_NPM_TARBALLS_VAR)
	file(READ "${DERAMMO_NPM_PACKAGE_DIR}/package.json" DERAMMO_NPM_PACKAGE_JSON)
	set(DERAMMO_NPM_NAMES "")
	set(DERAMMO_NPM_TARBALLS "")
	foreach(DERAMMO_NPM_DEPENDENCY_KIND dependencies devDependencies)
		string(JSON DERAMMO_NPM_DEPENDENCIES ERROR_VARIABLE DERAMMO_NPM_JSON_ERROR
			GET "${DERAMMO_NPM_PACKAGE_JSON}" ${DERAMMO_NPM_DEPENDENCY_KIND})
		if(DERAMMO_NPM_JSON_ERROR)
			continue()
		endif()
		string(JSON DERAMMO_NPM_DEPENDENCY_COUNT LENGTH "${DERAMMO_NPM_DEPENDENCIES}")
		if(DERAMMO_NPM_DEPENDENCY_COUNT EQUAL 0)
			continue()
		endif()
		math(EXPR DERAMMO_NPM_DEPENDENCY_LAST "${DERAMMO_NPM_DEPENDENCY_COUNT} - 1")
		foreach(DERAMMO_NPM_DEPENDENCY_INDEX RANGE ${DERAMMO_NPM_DEPENDENCY_LAST})
			string(JSON DERAMMO_NPM_DEPENDENCY_NAME MEMBER "${DERAMMO_NPM_DEPENDENCIES}" ${DERAMMO_NPM_DEPENDENCY_INDEX})
			string(JSON DERAMMO_NPM_DEPENDENCY_VERSION GET "${DERAMMO_NPM_DEPENDENCIES}" "${DERAMMO_NPM_DEPENDENCY_NAME}")
			if(NOT DERAMMO_NPM_DEPENDENCY_VERSION MATCHES "^file:(.*\\.tgz)$")
				continue()
			endif()
			get_filename_component(DERAMMO_NPM_TARBALL "${CMAKE_MATCH_1}" ABSOLUTE BASE_DIR "${DERAMMO_NPM_PACKAGE_DIR}")
			list(APPEND DERAMMO_NPM_NAMES "${DERAMMO_NPM_DEPENDENCY_NAME}")
			list(APPEND DERAMMO_NPM_TARBALLS "${DERAMMO_NPM_TARBALL}")
		endforeach()
	endforeach()
	set(${DERAMMO_NPM_NAMES_VAR} "${DERAMMO_NPM_NAMES}" PARENT_SCOPE)
	set(${DERAMMO_NPM_TARBALLS_VAR} "${DERAMMO_NPM_TARBALLS}" PARENT_SCOPE)
endfunction()
