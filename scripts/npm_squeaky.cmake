# remove the installed dependencies and build outputs of the npm package or
# workspace root in DERAMMO_NPM_DIR, for `cmake -P` at build time: node_modules,
# dist, and the incremental state of every tsc configuration, which live next
# to the package as tsconfig.tsbuildinfo and tsconfig.<name>.tsbuildinfo; the
# glob runs here rather than at configure time so files created by builds
# since the last configure are found
cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED DERAMMO_NPM_DIR)
	message(FATAL_ERROR "npm_squeaky: DERAMMO_NPM_DIR not set")
endif()

file(GLOB DERAMMO_NPM_TSBUILDINFO
	"${DERAMMO_NPM_DIR}/tsconfig.tsbuildinfo"
	"${DERAMMO_NPM_DIR}/tsconfig.*.tsbuildinfo")
file(REMOVE_RECURSE
	"${DERAMMO_NPM_DIR}/dist"
	"${DERAMMO_NPM_DIR}/node_modules"
	${DERAMMO_NPM_TSBUILDINFO})
